# Frontend Helm Chart

* Chart deployes:
  * apache with drupal
  * secrets are initialzied at deployment. 

* Frontend [container](https://github.com/oda-hub/frontend-container) consists of the following components, and builds them with default make target:
  * an adapted [drupal](https://github.com/oda-hub/frontend-drupal7-for-astrooda) instance
  * with an [astrooda](https://github.com/oda-hub/frontend-astrooda) module
  * [bootstrap for astrooda](https://github.com/oda-hub/frontend-bootstrap_astrooda)

* Database:
  * [drupal database snapshot](https://github.com/oda-hub/frontend-drupal7-db-for-astrooda) as released 
  * database also contains help pages, as released with the given version. [Astrooda help pages](https://github.com/oda-hub/astrooda-help-pages) can be edited on dev instance of drupal, and stored in database snapshot on release.


[mysql](https://github.com/oda-hub/mysql-chart) chart should be deployed separately.
  
Secrets are used for drupal auth and [JWT token] signing, and are ingested in database and other drupal deployment settings.


If help pages are edited in production instance, the change will generally not be preserved. But snapshot of help pages can be extracted and stored in [a separate repository](https://gitlab.astro.unige.ch/oda/docs/help-pages). This repository can be [installed on deployment](https://github.com/oda-hub/astrooda-helppage-manager) to complement/override the help pages.

