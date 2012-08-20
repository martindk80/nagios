Misc. collection of nagios plugins
=================================

`check_redis.pl`
    * Simple netcat based Redis check with support for master/slave instances
    * Supports last save, last replication checks based on number of changes

Pacemaker
---------

`check_corosync.pl`
    * Simple corosync check, checks messaging rings and their status

`check_pacemaker.pl`
    * Originally based on [`check_crm_v0_5`](http://exchange.nagios.org/directory/Plugins/Clustering-and-High-2DAvailability/Check-CRM/details)
        * Removed Nagios::Plugin dependency
        * Added new error checks, improved error handling
        

