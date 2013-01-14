# == Class: opendj
#
# Module for deployment and configuration of ForgeRock OpenDJ.
#
# === Authors
#
# Conduct AS <iam-nsb@conduct.no>
#
# === Copyright
#
# Copyright (c) 2013 Conduct AS
#

class opendj (
  $opendj_ldap_host       = hiera('opendj_host', $::opendj_ldap_host),
  $opendj_ldap_port       = hiera('opendj_ldap_port', $::opendj_ldap_port),
  $opendj_admin_port      = hiera('opendj_admin_port', $::opendj_admin_port),
  $opendj_jmx_port        = hiera('opendj_jmx_port', $::opendj_jmx_port),
  $opendj_admin_user      = hiera('opendj_admin_user', $::opendj_admin_user),
  $opendj_admin_password  = hiera('opendj_admin_password', $::opendj_admin_password),
) {

  # FIXME: Should use the encode-password utility to generate a salted hash (SSHA512),
  # however this would result in a unique hash after each run resulting in frequent
  # and unnecessary changes of config.ldif. Need to find a better way to handle this.
  #
  # `su opendj -c "/var/lib/opendj/bin/encode-password -s SSHA512 -c foobarbaz" | awk '{ print $3 }' | cut -d \" -f2`
  #
  # Hardcoded hash of `admin` for testing purposes.
  $opendj_admin_password_hash = "{SHA}0DPiKuNIrrVmD8IUCuw1hQxNqZc="

  $opendj_home                = '/var/lib/opendj'

  package { "opendj": ensure => present }

  file { "${opendj_home}/config/config.ldif":
    ensure  => present,
    content => template("${module_name}/config.ldif.erb"),
    require => Package["opendj"],
    owner   => 'opendj',
    group   => 'opendj',
    mode    => 0600,
  }
}
