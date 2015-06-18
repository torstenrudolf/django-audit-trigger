# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import django.contrib.postgres.fields.jsonb
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('audit', '0001_initial'),
    ]

    operations = [
        migrations.AlterField(
            model_name='auditlog',
            name='changed_fields',
            field=django.contrib.postgres.fields.jsonb.JSONField(null=True),
        ),
        migrations.AlterField(
            model_name='auditlogsubscriptionrule',
            name='is_registered',
            field=models.BooleanField(default=False, editable=False),
        ),
    ]
