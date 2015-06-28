from django.db import connection


def get_ip_address_from_request(request):
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        return x_forwarded_for.split(',')[0]
    else:
        return request.META.get('REMOTE_ADDR')


class SystemRegistryMetaClass(type):
    singleton_class = None

    def __new__(cls, *args, **kwargs):
        if cls.singleton_class:
            raise Exception('Only one SystemRegistry allowed!')
        cls.singleton_class = super().__new__(cls, *args, **kwargs)
        return cls.singleton_class


class SystemRegistry(metaclass=SystemRegistryMetaClass):
    _user = None
    _user_ip_address = None

    def __new__(cls, *args, **kwargs):
        raise Exception('Do not instanciate the SystemRegistry, but use the class.')

    @classmethod
    def user(cls):
        """:rtype: django.contrib.auth.models.User"""
        return cls._user

    @classmethod
    def user_pk_or_none_if_anonymous(cls):
        return (cls.user().is_authenticated() and cls.user().pk) or None

    @classmethod
    def user_model_or_none_if_anonymous(cls):
        return '{0.app_label}.{0.model_name}'.format(cls.user()._meta)

    @classmethod
    def user_ip_address(cls):
        return cls._user_ip_address

    @classmethod
    def _update_postgres_runtime_parameters(cls):
        """
        set the audit relevant parameters as postgres runtime variables
        """
        connection.cursor().execute(
            "SET app.name = 'django';"
            "SET app.user_pk = %(user_pk)s;"
            "SET app.user_model = %(user_model)s;"
            "SET app.user_ip_address = %(user_ip_address)s;",
            {'user_pk': cls.user_pk_or_none_if_anonymous(),
             'user_model': cls.user_model_or_none_if_anonymous(),
             'user_ip_address': cls.user_ip_address()})

    @classmethod
    def set_user_information_and_update_postgres_runtime_parameters(cls, user, user_ip_address):
        cls._user = user
        cls._user_ip_address = user_ip_address
        cls._update_postgres_runtime_parameters()


class AuditMiddleWare(object):
    def process_request(self, request):
        """
        put the current user information into the system registry
        """
        SystemRegistry.set_user_information_and_update_postgres_runtime_parameters(
            request.user, get_ip_address_from_request(request))
