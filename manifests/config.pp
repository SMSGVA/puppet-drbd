/*

== Definition: drbd::config

Drop simple configuration snippets in /etc/drbd.conf.d/

Parameters:
- *$name*: the name of the configuration file.
- *$content*: the configuration parameters to add to this file.

Example usage:

  include drbd::base

  drbd::config { "sync-rate":
    content => "common { syncer { rate 550M; } }",
  }


See also:
 - http://www.drbd.org/users-guide/
 - drbd.conf(5)

*/
define drbd::config ($ensure=present, $content) {

  file { "/etc/drbd.conf.d/${name}.conf":
    ensure  => $ensure,
    mode    => "0600",
    owner   => "root",
    content => "# file managed by puppet\n\n${content}\n",
    require => Package["drbd"],
    notify  => Service["drbd"],
  }

}
