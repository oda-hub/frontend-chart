Deployed **{{basename}}** to [{{oda_namespace}}](https://frontend-staging.obsuks1.unige.ch/mmoda/):

***

**{{ revision.commit }}**: 

{{ revision.message }}

| component | branch / commit | 
| :--: | :--: |
{% for k, v in version.items() -%} 
| [{{ k }}]({{ v.url }}) | {{ v.branch }} / {{ v.commit }} |
{% endfor %}


 :tada:
