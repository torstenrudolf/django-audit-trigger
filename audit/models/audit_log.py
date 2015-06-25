from django.db import models
from django.conf import settings
import django.contrib.postgres.fields


class OIDField(models.IntegerField):
    """
    Postgres OID type.
    """
    def db_type(self, connection):
        return 'oid'


class AuditLog(models.Model):
    """
    Stores the audit logs.

    Holds information which row/table has changed as well as the changeset.
    """
    db_schema_name = models.TextField()
    db_table_name = models.TextField()
    db_relid = OIDField(db_index=True, help_text='the object ID of the table that caused the trigger invocation')
    db_session_user_name = models.TextField()
    db_current_timestamp = models.DateTimeField(help_text='Start of db transaction')
    db_statement_timestamp  = models.DateTimeField(db_index=True, help_text='Start of sql statement')
    db_clock_timestamp = models.DateTimeField(help_text='Actual time when the trigger was run')
    db_transaction_id = models.BigIntegerField()

    db_client_addr = models.GenericIPAddressField()
    db_client_port = models.IntegerField()
    db_client_query = models.TextField()

    db_action = models.TextField(db_index=True)
    row_data = django.contrib.postgres.fields.JSONField()
    changed_fields = django.contrib.postgres.fields.JSONField(null=True)
    statement_only = models.TextField()

    app_name = models.TextField()
    app_user_model = models.TextField()
    app_user_pk = models.BigIntegerField(db_index=True)
    app_user_ip_address = models.GenericIPAddressField()

    def save(self, *args, **kwargs):
        raise NotImplementedError('This table is readonly.')
