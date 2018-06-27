module CloudController
  class ServiceKeyAccess < BaseAccess
    def read_for_update?(object, params=nil)
      admin_user?
    end

    def can_remove_related_object?(object, params=nil)
      read_for_update?(object, params)
    end

    def read_related_object_for_update?(object, params=nil)
      read_for_update?(object, params)
    end

    def update?(object, params=nil)
      admin_user?
    end

    # These methods should be called first to determine if the user's token has the appropriate scope for the operation

    def read_with_token?(_)
      admin_user? || admin_read_only_user? || has_read_scope? || global_auditor?
    end

    def create_with_token?(_)
      admin_user? || has_write_scope?
    end

    def read_for_update_with_token?(_)
      admin_user? || has_write_scope?
    end

    def can_remove_related_object_with_token?(*args)
      read_for_update_with_token?(*args)
    end

    def read_related_object_for_update_with_token?(*args)
      read_for_update_with_token?(*args)
    end

    def update_with_token?(_)
      admin_user? || has_write_scope?
    end

    def delete_with_token?(_)
      admin_user? || has_write_scope?
    end

    def index_with_token?(_)
      # This can return true because the index endpoints filter objects based on user visibilities
      true
    end

    def create?(service_key, params=nil)
      return true if admin_user?
      return false if service_key.in_suspended_org?
      service_key.service_instance.space.has_developer?(context.user)
    end

    def delete?(service_key)
      create?(service_key)
    end

    def read?(service_key)
      return true if admin_user? || admin_read_only_user?
      service_key.service_instance.space.has_developer?(context.user)
    end

    def read_env?(service_key)
      return true if admin_user? || admin_read_only_user?
      service_key.space.has_developer?(context.user)
    end

    def read_env_with_token?(service_key)
      read_with_token?(service_key)
    end

    def index?(_, params=nil)
      return true if admin_user? || admin_read_only_user?
      return true unless params && params.key?(:related_obj)
      params[:related_obj].space.has_developer?(context.user)
    end
  end
end
