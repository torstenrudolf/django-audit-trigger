from django.contrib.contenttypes.models import ContentType
from django.db import models
from django.contrib.postgres.fields import ArrayField
from django.db import connection, transaction


class AuditLogSubscriptionRule(models.Model):
    name = models.TextField(blank=False)
    model_content_type = models.ForeignKey(ContentType)
    is_registered = models.BooleanField(default=False, editable=False)

    log_query_text = models.BooleanField(default=False, verbose_name='Do you want to log the whole text of the sql query?')
    # todo
    # exclude_columns = ArrayField(models.TextField(blank=None))
    # audit_rows = models.BooleanField(default=True, help_text='Record each row change, or only audit at a statement level')

    def __unicode__(self):
        return "{self.name} (model: {self.model_content_type.model})".format(self=self)

    def register(self):
        """
        call the postgres function to create the trigger for the above auditing specs
        """
        assert not self.is_registered
        with transaction.atomic():
            cursor = connection.cursor()
            cursor.execute("SELECT audit.audit_table(%s)", [self.model_content_type.model_class()._meta.db_table])
            self.is_registered = True
            self.save()

    def deregister(self):
        """
        drop the trigger for the above auditing specs
        """
        assert self.is_registered
        with transaction.atomic():
            cursor = connection.cursor()
            drop_trigger_sql = "DROP TRIGGER audit_trigger_row ON {table}; " \
                               "DROP TRIGGER audit_trigger_stm ON {table};".format(
                table=self.model_content_type.model_class()._meta.db_table)
            print(drop_trigger_sql)
            cursor.execute(drop_trigger_sql)
            self.is_registered = False
            self.save()

    def delete(self, **kwargs):
        if self.is_registered:
            self.deregister()
        super().delete(**kwargs)
