from audit.models import AuditLog


class AuditedModelMixin(object):

    def get_all_audit_logs(self):
        return AuditLog.objects.for_model_instance(self)

