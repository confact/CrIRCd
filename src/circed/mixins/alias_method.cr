macro alias_method(new_method, old_method)
  def {{new_method.id}}(*args)
    {{old_method.id}}(*args)
  end

  def self.{{new_method.id}}(*args)
    {{old_method.id}}(*args)
  end
end
