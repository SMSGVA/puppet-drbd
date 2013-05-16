/*

== Definition: drbd::resource

Wrapper around drbd::config to ease the definition of DRBD resources. It also
initalizes the DRBD device if needed.

Note: you will still need to manually synchronize both DRBD volumes, format
the resulting device and mount it. This can be done with the following
commands:

  drbdadm -- --overwrite-data-of-peer primary $name
  mkfs.ext3 /dev/drbd/by-res/$name
  mount /dev/drbd/by-res/$name /mnt/

Parameters:
- *$name*: name of the resource.
- *ensure*: create or remove the resource. Defaults to present.
- *$host1*: one of the host's name
- *$host2*: the other hosts's name
- *$ip1*: $host1's IP address
- *$ip2*: $host2's IP address
- *$port*: the port used to communicate between the two nodes. Defaults to
  7789.
- *$secret*: a shared secret string.
- *$disk*: device to use as DRBD's low-level device.
- *$device*: name of the device defined by the current resource. Defaults to
  /dev/drbd0.
- *metadisk*: location of metadata. Defaults to internal.
- *$protocol*: protocol identifier for this resource (A, B or C). Defaults to
  C.
- *$manage*: whether this DRBD resource must be activated by puppet, if it
  happens to be down. Defaults to "true".
- *primary_on*: Which host(s) should the resource become primary on. Defaults
  to "false" so neither host becomes primary at resource initialization.
- *allow_two*: whether to allow resource to be primary on both hosts. Defaults
  to "false".
- *fence_peer*: script capable of fencing the resource.
- *after_resync*: script to unfence the resource.
- *fencing*: type of fencing to use. Defaults to "resource-only".

Example usage:

  include drbd::base

  drbd::resource { "my-drbd-volume":
    host1  => "bob.example.com",
    host2  => "alice.example.com",
    ip1    => "192.168.1.10", # bob's IP
    ip2    => "192.168.1.11", # alice's IP
    disk   => "/dev/vg0/my-drbd-lv",
    secret => "foobar",
  }

See also:
 - http://www.drbd.org/users-guide/
 - drbd.conf(5)

*/
define drbd::resource ($ensure=present, $host1, $host2, $ip1, $ip2, $port='7789', $secret=false, $disk, $device='/dev/drbd0', $metadisk='internal', $protocol='C', $manage=true, $primary_on=false, $allow_two=false, $fence_peer='/usr/lib/drbd/crm-fence-peer.sh', $after_resync='/usr/lib/drbd/crm-unfence-peer.sh', $fencing='resource-only') {

  drbd::config { "ZZZ-resource-${name}":
    content => template("drbd/drbd.conf.erb"),
  }
  case $ensure {
    present: {

      if $manage == true {

        # create metadata on device, except if resource seems already initalized.
        exec { "intialize DRBD metadata for $name":
          command => "drbdadm create-md $name",
          onlyif  => "test -e $disk",
          unless  => "drbdadm dump-md $name || (drbdadm cstate $name | egrep -q '^(Sync|Connected)')",
          before  => Service["drbd"],
          require => [
          Exec["load drbd module"],
            Drbd::Config["ZZZ-resource-${name}"],
          ],
        }

        exec { "enable DRBD resource $name":
          command => "drbdadm up $name",
          onlyif  => "drbdadm dstate $name | egrep -q '^Diskless/|^Unconfigured'",
          before  => Service["drbd"],
          require => [
            Exec["intialize DRBD metadata for $name"],
          Exec["load drbd module"],
          ],
        }

      }
    }
    absent: {
      Drbd::Config[ "ZZZ-resource-${name}" ] {
        ensure  => absent,
        require => Exec[ "remove DRBD metadata for $name" ],
      }
      exec { "disable DRBD resource $name":
        command => "drbdadm down $name",
        unless  => [
          "drbdadm dstate $name | grep -q Unconfigured",
          "drbdadm role $name | grep -q Primary",
        ],
        onlyif  => "drbdadm role $name 1>/dev/null 2>/dev/null",
        notify  => Exec[ "remove DRBD metadata for $name" ],
        before  => Service['drbd'],
      }
      exec { "remove DRBD metadata for $name":
        command     => "drbdadm wipe-md $name",
        onlyif      => "drbdadm dstate $name | grep -q Unconfigured",
        refreshonly => true,
        require     => Exec[ "disable DRBD resource $name" ],
      }
    }
  }

  iptables { "allow drbd from $host1 on port $port":
    proto  => "tcp",
    dport  => $port,
    source => $ip1,
    jump   => "ACCEPT",
  }

  iptables { "allow drbd from $host2 on port $port":
    proto  => "tcp",
    dport  => $port,
    source => $ip2,
    jump   => "ACCEPT",
  }

}
