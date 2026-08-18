defmodule SeedFactory.ExistingEntityConflictTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :widget_bundle can be produced together with :widget or standalone, so with
    # a :widget already in the context only the standalone command stays valid.
    command :create_widget do
      resolve(fn _ ->
        {:ok, %{widget: "widget"}}
      end)

      produce :widget
    end

    command :create_widget_and_bundle do
      resolve(fn _ ->
        {:ok, %{widget: "widget from bundle", widget_bundle: "bundle with widget"}}
      end)

      produce :widget
      produce :widget_bundle
    end

    command :create_widget_bundle_only do
      resolve(fn _ ->
        {:ok, %{widget_bundle: "standalone bundle"}}
      end)

      produce :widget_bundle
    end
  end

  use SeedFactory.Test, schema: Schema

  test "excludes commands from conflict group when they would produce existing entities",
       context do
    context = produce(context, :widget)

    assert context.widget == "widget"

    context = produce(context, :widget_bundle)

    assert context.widget_bundle == "standalone bundle"
  end
end
