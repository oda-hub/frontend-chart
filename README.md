# Frontend Helm Chart

* Chart deployes:
  * apache with drupal
  * secrets are initialzied at deployment. 

* Frontend [container](https://github.com/oda-hub/frontend-container) consists of the following components, and builds them with default make target:
  * an adapted [drupal](https://github.com/oda-hub/mmoda-frontend-drupal) instance
  * with an [mmoda](https://github.com/oda-hub/mmoda-frontend-module) module
  * [bootstrap for mmoda](https://github.com/oda-hub/mmoda-frontend-theme)
  * [setttings.php.template]() is delivered instead of settings.php, which may contain private data. It is filled in on deployment with information.
  
* Database:
  * [drupal database snapshot](https://github.com/oda-hub/mmoda-frontend-db) as released 
  * database also contains help pages, as released with the given version. [Astrooda help pages](https://github.com/oda-hub/astrooda-help-pages) can be edited on dev instance of drupal, and stored in database snapshot on release.
  * user accounts recreated on deployment. backed-up and maintainer during service upgrades.
  
* Frontend extensions, corresponding to individual instruments, can be disabled at deployment, see [there](https://github.com/oda-hub/frontend-chart/blob/master/make.sh#L70).

[mysql](https://github.com/oda-hub/mysql-chart) chart should be deployed separately.

Please beware:

*  The resulting page served under /mmoda
*  If there is a problem with opening the frontend, manual changes to drupal7_sites_default_settings.php.template may be needed: at least base_url and reverse_proxy_addresses
*  With every change, it will be necessary to do `drush cc` - see in make.sh.
  
Secrets are used for drupal auth and [JWT token] signing, and should be ingested in database and other drupal deployment settings.


If help pages are edited in production instance, the change will generally not be preserved. But snapshot of help pages can be extracted and stored in [a separate repository](https://gitlab.astro.unige.ch/oda/docs/help-pages). This repository can be [installed on deployment](https://github.com/oda-hub/astrooda-helppage-manager) to complement/override the help pages.

