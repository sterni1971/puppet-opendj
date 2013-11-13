# == Class: opendj
#
# Module for deployment and configuration of ForgeRock OpenDJ.
#
# === Authors
#
# Eivind Mikkelsen <eivindm@conduct.no>
#
# === Copyright
#
# Copyright (c) 2013 Conduct AS
#

class opendj (
  $ldap_port       = hiera('opendj::ldap_port', '1389'),
  $ldaps_port      = hiera('opendj::ldaps_port', '1636'),
  $admin_port      = hiera('opendj::admin_port', '4444'),
  $repl_port       = hiera('opendj::repl_port', '8989'),
  $jmx_port        = hiera('opendj::jmx_port', '1689'),
  $admin_user      = hiera('opendj::admin_user', 'cn=Directory Manager'),
  $admin_password  = hiera('opendj::admin_password'),
  $base_dn         = hiera('opendj::base_dn'),
  $home            = hiera('opendj::home', '/opt/opendj'),
  $user            = hiera('opendj::user', 'opendj'),
  $group           = hiera('opendj::group', 'opendj'),
  $host            = hiera('opendj::host'),
  $tmp		         = hiera('opendj::tmpdir', '/dev/shm'),
  $master          = hiera('opendj::master', undef),
) {
  $su          = "/bin/su ${opendj::user} -s /bin/bash"
  $common_opts = "-h ${fqdn} -D '${opendj::admin_user}' -w ${opendj::admin_password}"
  $ldapsearch  = "${opendj::home}/bin/ldapsearch ${common_opts} -p ${opendj::ldap_port}"
  $ldapmodify  = "${opendj::home}/bin/ldapmodify ${common_opts} -p ${opendj::ldap_port}"
  $dsconfig    = "${opendj::home}/bin/dsconfig   ${common_opts} -p ${opendj::admin_port} -X -n"
  $dsreplication = "$su ${opendj::home}/bin/dsreplication --adminUID admin --adminPassword ${admin_password}"

  package { "opendj":
    ensure => present,
  }

  file { "${home}":
    ensure => directory,
    owner => $user,
    group => $group,
    require => Package["opendj"]
  }

  file { "${tmp}/opendj.properties":
    ensure => file,
    content => template("${module_name}/setup.erb"),
    owner  => $user,
    group  => $group,
    mode => 0600,
    require => File["${home}"],
  }

  file { "${tmp}/base_dn.ldif":
    ensure => file,
    content => template("${module_name}/base_dn.ldif.erb"),
    owner => $user,
    group => $group,
    mode => 0600
  }

  exec { "configure opendj":
    require => File["${tmp}/opendj.properties"],
    command => "/bin/su opendj -s /bin/bash -c '${home}/setup -i \
        -n -Q --acceptLicense --propertiesFilePath /dev/shm/opendj.properties'",
    creates => "${home}/config",
    notify => Exec['create base dn'],
  }

  exec { "create base dn":
    require => File["${tmp}/base_dn.ldif"],
    command => "${home}/bin/ldapmodify -a -D '${admin_user}' \
	    -w '${admin_password}' -h ${fqdn} -p ${ldap_port} -f '${tmp}/base_dn.ldif'",
    refreshonly => true,
  }

  exec { "set single structural objectclass behavior":
    command => "${dsconfig} --advanced set-global-configuration-prop --set single-structural-objectclass-behavior:accept",
    unless  => "${dsconfig} --advanced get-global-configuration-prop | grep 'single-structural-objectclass-behavior : accept'",
    require => Exec["configure opendj"]
  }

  if ($fqdn != $master) {
    exec { "enable replication": 
      command => "$su $dsreplication \
        --host1 ${opendj::master} --port1 ${opendj::admin_port} \
        --replicationPort1 ${opendj::repl_port} \
        --bindDN1 ${admin_user} --bindPassword1 ${admin_password} \
        --host2 ${fqdn} --port2 ${opendj::admin_port} \
        --replicationPort2 ${opendj::repl_port} \
        --bindDN2 ${opendj::admin_user} --bindPassword2 ${opendj::admin_password} \
        --baseDN "${opendj::base_dn}" -X -n",
    }
  }
}
