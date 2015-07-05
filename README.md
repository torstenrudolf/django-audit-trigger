# django-audit-trigger
Combining a postgres audit trigger and django

## why another django audit app?
Using a database trigger for auditing has various advantages over an app driven auditing. 
* it means no extra traffic between app and db server
* the app can't bypass the auditing
* the saved audit data is the "truth" - it captures the changes on db level

In [django-postgres](bitbucket.org/schinckel/django-postgres) Matthew Schinkel wrote an auditing app based on the same postgres audit trigger used here. But I wanted to have it as a standalone django app and using django.contrib.postgres. django-audit-trigger also has a different mechanism to manage audit subscriptions of models.

# Requirements
* django>=1.9 (currently the dev trunk)
* postgres>=9.4

# the postgres trigger
django-audit-trigger uses a slightly modified version of the [Audit trigger 91plus](https://wiki.postgresql.org/wiki/Audit_trigger_91plus). Instead of hstore fields the trigger is modified to use jsonb fields.

# Auditing your models
## How to subscribe your model for auditin
todo

## Querying the audit logs
You might want to use the `audit.models.mixins.AuditedModelMixin` for audit log query helpers.
