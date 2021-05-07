# Frontend Helm Chart

Frontend [container](https://gitlab.astro.unige.ch/oda/frontend/frontend-container) consists of the following components:
* an adapted [drupal](https://github.com/oda-hub/frontend-drupal7-for-astrooda) instance
* with an [astrooda](https://github.com/oda-hub/frontend-astrooda) module
* [bootstrap for astrooda](https://gitlab.astro.unige.ch/oda/frontend/bootstrap_astrooda)
* [drupal database snapshot](https://github.com/oda-hub/frontend-drupal7-db-for-astrooda) as released 
  * database also contains help pages, as released with the given version.
  * The [astrooda help pages](https://github.com/oda-hub/astrooda-help-pages) can be edited on dev instance of drupal, and stored in database snapshot on release.

* chart deployes:
  * apache with drupal
  * mariadb
  * secrets are initialzied at deployment. 
  
Secrets are used for drupal auth and [JWT token] signing, and are ingested in database and other drupal deployment settings.


If help pages are edited in production instance, the change will generally not be preserved. But snapshot of help pages can be extracted and stored in [a separate repository](https://gitlab.astro.unige.ch/oda/docs/help-pages). This repository can be [installed on deployment](https://github.com/oda-hub/astrooda-helppage-manager) to complement/override the help pages.

