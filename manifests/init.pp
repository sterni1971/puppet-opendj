# == Class: opendj
#
# Module for deployment and configuration of ForgeRock OpenDJ.
#
# === Authors
#
# Eivind Mikkelsen <eivindm@conduct.no>
# Sven Sternberger <sven.sternberger@desy.de>
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
  $host            = hiera('opendj::host', $::fqdn),
  $master          = hiera('opendj::master', undef),
) {
  $common_opts   = "-h ${host} -D '${opendj::admin_user}' -w ${opendj::admin_password}"
  $ldapsearch    = "${opendj::home}/bin/ldapsearch ${common_opts} -p ${opendj::ldap_port}"
  $ldapmodify    = "${opendj::home}/bin/ldapmodify ${common_opts} -p ${opendj::ldap_port}"
  $dsconfig      = "${opendj::home}/bin/dsconfig   ${common_opts} -p ${opendj::admin_port} -X -n"
  $dsreplication = "${opendj::home}/bin/dsreplication --adminUID admin --adminPassword ${admin_password} -X -n"


  # install package
  package { "opendj":
    ensure => present,
  }

  # create user, group and set homedir
  group { "${group}":
    ensure => "present",
  } ->
  user { "${user}":
    ensure     => "present",
    groups     => $group,
    home       => $home,
    managehome => true,
  } ->
  file { "${home}":
    ensure  => directory,
    owner   => $user,
    group   => $group,
    recurse => true,
    require => Package["opendj"],
  }
  
  # write configuration and apply
  file { "${home}/opendj.properties":
    ensure  => file,
    content => template("${module_name}/setup.erb"),
    owner   => $user,
    group   => $group,
    mode    => 0600,
    require => File["${home}"],
  }

  file { "${home}/base_dn.ldif":
    ensure  => file,
    content => template("${module_name}/base_dn.ldif.erb"),
    owner   => $user,
    group   => $group,
    mode    => 0600,
    require => [File["${home}"], Service['opendj']],
  }

  file { 'opendj.limits':
    path    => '/etc/security/limits.d/10-opendj',
    content => "${user} soft nofile 65536\n${user} hard nofile 131072\n",
  } 
  
  exec { "configure opendj":
    command => "/bin/su opendj -s /bin/bash -c '${home}/setup -i \
        -n -Q --acceptLicense --doNotStart --propertiesFilePath ${home}/opendj.properties'",
    creates => "${home}/config",
    require => File["${home}/opendj.properties"],
  }
  
  exec { "create RC script":
    command => "${home}/bin/create-rc-script --userName ${user} \
        --outputFile /etc/init.d/opendj",
    creates => "/etc/init.d/opendj",
    require => Package["opendj"],
  }
  
  # start service
  service { 'opendj':
    enable     => true,
    ensure     => running,
    hasrestart => true,
    hasstatus  => false,
    status     => "${home}/bin/status -D \"${admin_user}\" \
        --bindPassword ${admin_password} | grep --quiet Started",
    require    => [Exec['create RC script',"configure opendj"],File["${home}",'opendj.limits']]
  }
  
  # post configuration
  exec { "reject unauthenticated requests":
    command => "$dsconfig set-global-configuration-prop --set reject-unauthenticated-requests:true",
    unless  => "$dsconfig get-global-configuration-prop --property reject-unauthenticated-requests| grep true",
    require => Service['opendj'],
  }
  
  exec { "set single structural objectclass behavior":
    command => "${dsconfig} --advanced set-global-configuration-prop --set single-structural-objectclass-behavior:accept",
    unless  => "${dsconfig} --advanced get-global-configuration-prop --property single-structural-objectclass-behavior | grep accept",
    require => Service['opendj'],
  }
  
  exec { "create base dn":
    command => "${home}/bin/ldapmodify -a -D '${admin_user}' \
        -w '${admin_password}' -h ${host} -p ${ldap_port} -f '${home}/base_dn.ldif'",
    unless  => "$ldapsearch -b '$base_dn' '&(objectclass=top)'|grep $base_dn",
    require => [File["${home}/base_dn.ldif"],Service['opendj']],
  }

  # configure replication
  if ($master != '' and $host != $master) {
   exec { "enable replication":
      command => "/bin/su ${user} -s /bin/bash -c \"$dsreplication enable \
        --host1 ${master} --port1 ${admin_port} \
        --replicationPort1 ${repl_port} \
        --bindDN1 '${admin_user}' --bindPassword1 ${admin_password} \
        --host2 ${host} --port2 ${admin_port} \
        --replicationPort2 ${repl_port} \
        --bindDN2 '${admin_user}' --bindPassword2 ${admin_password} \
        --baseDN '${base_dn}'\"",
      unless => "/bin/su ${user} -s /bin/bash -c \"$dsreplication \
        status | grep ${host} | cut -d : -f 5 | grep true\"",
      require => Service['opendj'],
    } ~>
    exec { "initialize replication":
      command => "/bin/su ${user} -s /bin/bash -c \"$dsreplication initialize \
        -h ${master} -p ${admin_port} -O ${host} --baseDN '${base_dn}'\"",
      refreshonly => true,
    }
  }
}
