# Test helper for clean repository access in tests
module RepositoryHelper
  # Get channel repository for test setup
  def channel_repository
    Circed::Infrastructure::ServiceLocator.channel_repository
  end

  # Get user repository for test setup
  def user_repository
    Circed::Infrastructure::ServiceLocator.user_repository
  end

  # Clean setup/teardown methods
  def clear_repositories
    channel_repository.clear
    user_repository.clear
  end

  # Helper methods for common test operations
  def create_test_channel(name : String) : Circed::Domain::Channel
    channel_repository.create_channel(name)
  end

  def create_test_channel_with_user(channel_name : String, user_nickname : String, operator : Bool = true) : Circed::Domain::Channel
    channel = create_test_channel(channel_name)
    channel.add_member(user_nickname)
    if operator
      channel.members[user_nickname] << 'o'
    end
    channel
  end

  def user_in_channel?(channel_name : String, user_nickname : String) : Bool
    if channel = channel_repository.get(channel_name)
      channel.has_member?(user_nickname)
    else
      false
    end
  end

  def channel_empty?(channel_name : String) : Bool
    if channel = channel_repository.get(channel_name)
      channel.is_empty?
    else
      true
    end
  end

  def get_test_channel(channel_name : String) : Circed::Domain::Channel?
    channel_repository.get(channel_name)
  end
end
