defmodule SeedFactory.SchemaTest do
  use ExUnit.Case, asyn: true

  test "persisted data" do
    assert Spark.Dsl.Extension.get_persisted(SchemaExample, :entities) == %{
             office: :create_office,
             org: :create_org,
             project: :publish_project,
             draft_project: :create_draft_project,
             user: :create_user
           }

    assert Spark.Dsl.Extension.get_persisted(SchemaExample, :commands) == %{
             activate_user: %SeedFactory.Command{
               deleting_instructions: [],
               name: :activate_user,
               params: %{
                 user: %SeedFactory.Parameter{map: nil, name: :user, params: %{}, source: :user}
               },
               producing_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_DB83438079384E34AA22969B593E86B2/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
               ]
             },
             create_draft_project: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_draft_project,
               params: %{
                 name: %SeedFactory.Parameter{
                   map: nil,
                   name: :name,
                   params: %{},
                   source: &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0
                 },
                 office: %SeedFactory.Parameter{
                   map: nil,
                   name: :office,
                   params: %{},
                   source: :office
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :draft_project, from: :project}
               ],
               resolve: &SchemaExample.resolve_0_generated_F9B92FE2B5FD0A57A27FB751FF0F0F04/1,
               updating_instructions: []
             },
             create_office: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_office,
               params: %{
                 name: %SeedFactory.Parameter{
                   map: nil,
                   name: :name,
                   params: %{},
                   source: &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0
                 },
                 org: %SeedFactory.Parameter{map: nil, name: :org, params: %{}, source: :org}
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :office, from: :office}
               ],
               resolve: &SchemaExample.resolve_0_generated_DE3F3BC82EB1A0ECFC65DA3209C3BCF5/1,
               updating_instructions: []
             },
             create_org: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_org,
               params: %{
                 address: %SeedFactory.Parameter{
                   map: nil,
                   name: :address,
                   params: %{
                     city: %SeedFactory.Parameter{
                       map: nil,
                       name: :city,
                       params: %{},
                       source:
                         &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0
                     },
                     country: %SeedFactory.Parameter{
                       map: nil,
                       name: :country,
                       params: %{},
                       source:
                         &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0
                     }
                   },
                   source: nil
                 },
                 name: %SeedFactory.Parameter{
                   map: nil,
                   name: :name,
                   params: %{},
                   source: &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :org, from: :org}
               ],
               resolve: &SchemaExample.resolve_0_generated_C9E261A7CEB6327F8844F3B180B40C30/1,
               updating_instructions: []
             },
             create_user: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_user,
               params: %{
                 name: %SeedFactory.Parameter{
                   map: nil,
                   name: :name,
                   params: %{},
                   source: &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0
                 },
                 office_id: %SeedFactory.Parameter{
                   map: &SchemaExample.map_0_generated_16C1099E6C1F2F2BF413FCD46A594112/1,
                   name: :office_id,
                   params: %{},
                   source: :office
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :user, from: :user}
               ],
               resolve: &SchemaExample.resolve_0_generated_C6863B90DC6B70859AEA378FC9A9DF24/1,
               updating_instructions: []
             },
             publish_project: %SeedFactory.Command{
               deleting_instructions: [%SeedFactory.DeletingInstruction{entity: :draft_project}],
               name: :publish_project,
               params: %{
                 project: %SeedFactory.Parameter{
                   map: nil,
                   name: :project,
                   params: %{},
                   source: :draft_project
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :project, from: :project}
               ],
               resolve: &SchemaExample.resolve_0_generated_A5D8F24A9A1826648663280E85EEFD7A/1,
               updating_instructions: []
             },
             raise_exception: %SeedFactory.Command{
               deleting_instructions: [],
               name: :raise_exception,
               params: %{},
               producing_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_9B193121A70CFA40AEB7E70819330466/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
               ]
             },
             resolve_with_error: %SeedFactory.Command{
               deleting_instructions: [],
               name: :resolve_with_error,
               params: %{},
               producing_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_86DFA5551DF1E7069C035938144FEFFE/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
               ]
             }
           }
  end

  describe "validations" do
    test "command without resolve arg" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema1]
         commands -> command -> action1:
          required :resolve option not found, received options: [:name]
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema1 do
            use SeedFactory.Schema

            command :action1 do
            end
          end
        end
      )
    end

    test "commands with duplicated names" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema2]
         commands -> command -> action1:
          duplicated command name
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema2 do
            use SeedFactory.Schema

            command :action1 do
              resolve(fn _args -> {:ok, %{}} end)

              update :user, from: :user
            end

            command :action1 do
              resolve(fn _args -> {:ok, %{}} end)

              update :user, from: :user
            end
          end
        end
      )
    end

    test "different commands produce the same entity" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema3]
         commands -> command -> action2 -> produce -> foo:
          only 1 command can produce the entity. Entity :foo can already be produced by :action1
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema3 do
            use SeedFactory.Schema

            command :action1 do
              produce :foo, from: :foo
              resolve(fn _args -> {:ok, %{}} end)
            end

            command :action2 do
              produce :foo, from: :foo
              resolve(fn _args -> {:ok, %{}} end)
            end
          end
        end
      )
    end

    test "command without produce and update directives" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.Command]
         commands -> command -> action1:
          at least 1 produce or update directive must be set
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema4 do
            use SeedFactory.Schema

            command :action1 do
              resolve(fn _args -> {:ok, %{}} end)
            end
          end
        end
      )
    end

    test "cyclic dependency with multiple commands" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema5]
         commands:
          found dependency cycles:
          * :create_project - :create_user - :create_org
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema5 do
            use SeedFactory.Schema

            command :create_user do
              param(:org, :org)
              resolve(fn _args -> {:ok, %{}} end)

              produce :user, from: :user
            end

            command :create_project do
              param(:created_by, :user)

              resolve(fn _args -> {:ok, %{}} end)

              produce :project, from: :project
            end

            command :create_file do
              param(:project, :project)
              param(:created_by, :user)

              resolve(fn _args -> {:ok, %{}} end)

              produce :file, from: :file
            end

            command :create_org do
              param(:primary_project, :project)

              resolve(fn _args -> {:ok, %{}} end)

              produce :org, from: :org
            end
          end
        end
      )
    end

    test "cyclic dependency with 1 command" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema6]
         commands:
          found dependency cycles:
          * :create_user
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema6 do
            use SeedFactory.Schema

            command :create_user do
              param(:user, :user)
              resolve(fn _args -> {:ok, %{}} end)

              produce :user, from: :user
            end
          end
        end
      )
    end
  end
end
