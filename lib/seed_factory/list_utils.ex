defmodule SeedFactory.ListUtils do
  @moduledoc false

  def intersection(list1, list2) do
    list1 -- (list1 -- list2)
  end
end
