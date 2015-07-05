from __future__ import unicode_literals

from django.db import models

from audit.models.mixins import AuditedModelMixin


class AuditMe(AuditedModelMixin, models.Model):

    name = models.CharField(max_length=128)
    code = models.CharField(max_length=16)