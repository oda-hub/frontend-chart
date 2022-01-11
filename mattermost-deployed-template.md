Deployed **{{basename}}** to [{{oda_namespace}}](https://frontend-staging.obsuks1.unige.ch/mmoda/):

***

frontend-container/version.yaml

| component | branch / commit | 
| :--: | :--: |
{% for k, v in version.items() %}
| [{{ k }}]({{ v.url }}) | {{ v.branch }} / {{ v.commit }} |
{% endfor %}

***