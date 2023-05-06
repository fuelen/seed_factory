defmodule SeedFactory.Params do
  @moduledoc false
  def index_by_name(list) do
    Map.new(list, &{&1.name, &1})
  end
end
