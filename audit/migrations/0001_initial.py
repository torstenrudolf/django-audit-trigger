# -*- coding: utf-8 -*-
from __future__ import unicode_literals
import os

import audit.models.audit_log
import django.contrib.postgres.fields.jsonb
from django.db import migrations, models


with open(os.path.join(os.path.dirname(__file__), 'audit_trigger.sql'), 'r') as f:
    audit_trigger_sql = f.read()


class Migration(migrations.Migration):

    dependencies = [
        ('contenttypes', '0002_remove_content_type_name'),
    ]

    operations = [
        migrations.CreateModel(
            name='AuditLog',
            fields=[
                ('id', models.AutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('db_schema_name', models.TextField()),
                ('db_table_name', models.TextField()),
                ('db_relid', audit.models.audit_log.OIDField(db_index=True, help_text='the object ID of the table that caused the trigger invocation')),
                ('db_session_user_name', models.TextField()),
                ('db_current_timestamp', models.DateTimeField(help_text='Start of db transaction')),
                ('db_statement_timestamp', models.DateTimeField(db_index=True, help_text='Start of sql statement')),
                ('db_clock_timestamp', models.DateTimeField(help_text='Actual time when the trigger was run')),
                ('db_transaction_id', models.BigIntegerField()),
                ('db_client_addr', models.GenericIPAddressField()),
                ('db_client_port', models.IntegerField()),
                ('db_client_query', models.TextField()),
                ('db_action', models.TextField(db_index=True)),
                ('row_data', django.contrib.postgres.fields.jsonb.JSONField()),
                ('changed_fields', django.contrib.postgres.fields.jsonb.JSONField(null=True)),
                ('statement_only', models.TextField()),
                ('app_name', models.TextField()),
                ('app_user_model', models.TextField()),
                ('app_user_pk', models.BigIntegerField(db_index=True)),
                ('app_user_ip_address', models.GenericIPAddressField()),
            ],
        ),
        migrations.CreateModel(
            name='AuditLogSubscriptionRule',
            fields=[
                ('id', models.AutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.TextField()),
                ('is_registered', models.BooleanField(default=False, editable=False)),
                ('log_query_text', models.BooleanField(default=False, verbose_name='Do you want to log the whole text of the sql query?')),
                ('model_content_type', models.ForeignKey(to='contenttypes.ContentType')),
            ],
        ),
        migrations.RunSQL(sql=audit_trigger_sql)
    ]
