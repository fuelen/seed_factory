defmodule SeedFactory.SchemaTest do
  use ExUnit.Case, asyn: true

  test "persisted data" do
    assert Spark.Dsl.Extension.get_persisted(SchemaExample, :entities) == %{
             office: :create_office,
             org: :create_org,
             project: :publish_project,
             draft_project: :create_draft_project,
             user: :create_user,
             profile: :create_user,
             virtual_file: :create_virtual_file
           }

    assert Spark.Dsl.Extension.get_persisted(SchemaExample, :commands) == %{
             activate_user: %SeedFactory.Command{
               deleting_instructions: [],
               name: :activate_user,
               params: %{
                 user: %SeedFactory.Parameter{
                   map: nil,
                   name: :user,
                   params: %{},
                   source: :user,
                   with_traits: [:pending]
                 },
                 finances: %SeedFactory.Parameter{
                   name: :finances,
                   source: nil,
                   params: %{
                     plan: %SeedFactory.Parameter{
                       name: :plan,
                       source:
                         &SchemaExample.source_0_generated_0C48BED8A12F038606F3E4AF905059F7/0,
                       params: %{},
                       map: nil,
                       with_traits: nil
                     }
                   },
                   map: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_A318D00A9A01DC9FF758958FF2E3647B/1,
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
                   source: &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                   with_traits: nil
                 },
                 office: %SeedFactory.Parameter{
                   map: nil,
                   name: :office,
                   params: %{},
                   source: :office,
                   with_traits: nil
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
                   source: &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                   with_traits: nil
                 },
                 org: %SeedFactory.Parameter{
                   map: nil,
                   name: :org,
                   params: %{},
                   source: :org,
                   with_traits: nil
                 }
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
                         &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                       with_traits: nil
                     },
                     country: %SeedFactory.Parameter{
                       map: nil,
                       name: :country,
                       params: %{},
                       source:
                         &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                       with_traits: nil
                     }
                   },
                   source: nil,
                   with_traits: nil
                 },
                 name: %SeedFactory.Parameter{
                   map: nil,
                   name: :name,
                   params: %{},
                   source: &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                   with_traits: nil
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
                   source: &SchemaExample.source_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                   with_traits: nil
                 },
                 office_id: %SeedFactory.Parameter{
                   map: &SchemaExample.map_0_generated_16C1099E6C1F2F2BF413FCD46A594112/1,
                   name: :office_id,
                   params: %{},
                   source: :office,
                   with_traits: nil
                 },
                 contacts_confirmed?: %SeedFactory.Parameter{
                   name: :contacts_confirmed?,
                   source: &SchemaExample.source_0_generated_04DBDDDB37365C52E20F9B2A5356E5C4/0,
                   params: %{},
                   map: nil,
                   with_traits: nil
                 },
                 role: %SeedFactory.Parameter{
                   name: :role,
                   source: &SchemaExample.source_0_generated_798FA5AC2FD46821DD81B004373E764A/0,
                   params: %{},
                   map: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :user, from: :user},
                 %SeedFactory.ProducingInstruction{entity: :profile, from: :profile}
               ],
               resolve: &SchemaExample.resolve_0_generated_B56A668B5121BBAD14A602F47827541E/1,
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
                   source: :draft_project,
                   with_traits: nil
                 },
                 published_by: %SeedFactory.Parameter{
                   name: :published_by,
                   source: :user,
                   params: %{},
                   map: nil,
                   with_traits: [:active]
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :project, from: :project}
               ],
               resolve: &SchemaExample.resolve_0_generated_499072EB572D4497C8697813784328E1/1,
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
             },
             create_virtual_file: %SeedFactory.Command{
               name: :create_virtual_file,
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :virtual_file, from: :file}
               ],
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :project, from: :project}
               ],
               deleting_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_2B36E339936F23FD426D06D5490D9BC3/1,
               params: %{
                 author: %SeedFactory.Parameter{
                   name: :author,
                   source: :user,
                   params: %{},
                   map: nil,
                   with_traits: [:active, :admin]
                 },
                 content: %SeedFactory.Parameter{
                   name: :content,
                   source: &SchemaExample.source_0_generated_0989761FCDF7BA5D3C1BD3C8885F03BC/0,
                   params: %{},
                   map: nil,
                   with_traits: nil
                 },
                 privacy: %SeedFactory.Parameter{
                   name: :privacy,
                   source: &SchemaExample.source_0_generated_391F8284104414D202A3E9E8FBD06D2C/0,
                   params: %{},
                   map: nil,
                   with_traits: nil
                 },
                 project: %SeedFactory.Parameter{
                   name: :project,
                   source: :project,
                   params: %{},
                   map: nil,
                   with_traits: nil
                 }
               }
             },
             delete_user: %SeedFactory.Command{
               name: :delete_user,
               producing_instructions: [],
               updating_instructions: [],
               deleting_instructions: [%SeedFactory.DeletingInstruction{entity: :user}],
               resolve: &SchemaExample.resolve_0_generated_BB7D80C861BBA279E03166977C76BBCF/1,
               params: %{
                 user: %SeedFactory.Parameter{
                   name: :user,
                   source: :user,
                   params: %{},
                   map: nil,
                   with_traits: [:active]
                 }
               }
             },
             suspend_user: %SeedFactory.Command{
               name: :suspend_user,
               producing_instructions: [],
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
               ],
               deleting_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_C0BEBF480312AD1B637AF84555E857BE/1,
               params: %{
                 user: %SeedFactory.Parameter{
                   name: :user,
                   source: :user,
                   params: %{},
                   map: nil,
                   with_traits: [:active]
                 }
               }
             }
           }
  end

  describe "validations" do
    test "command without resolve arg" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema1]
         root -> command -> action1:
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
         root -> command -> action1:
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
         root -> command -> action2 -> produce -> foo:
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

    test "command without produce, update and delete directives" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.Command]
         root -> command -> action1:
          at least 1 produce, update or delete directive must be set
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
      prefix =
        Regex.escape(
          "[SeedFactory.SchemaTest.MySchema5]\n root:\n  found dependency cycles:\n  * "
        )

      assert_raise(
        Spark.Error.DslError,
        ~r"#{prefix}((:create_user - :create_org - :create_project)|(:create_project - :create_user - :create_org)|(:create_org - :create_project - :create_user))$",
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
         root:
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

    test "duplicated traits" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema7]
         root -> trait -> pending -> user:
          duplicated trait
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema7 do
            use SeedFactory.Schema

            trait :pending, :user do
              exec(:create_user)
            end

            trait :pending, :user do
              exec(:create_user)
            end
          end
        end
      )
    end

    test "multiple instructions for the same entity within the command" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.Command]
         root -> command -> create_user:
          cannot apply multiple instructions on the same entity (:user)
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema7 do
            use SeedFactory.Schema

            command :create_user do
              param(:user, :user)
              resolve(fn _args -> {:ok, %{}} end)

              produce :user, from: :user
              update :user, from: :user
            end
          end
        end
      )

      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.Command]
         root -> command -> create_user:
          cannot apply multiple instructions on the same entity (:user)
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema8 do
            use SeedFactory.Schema

            command :create_user do
              param(:user, :user)
              resolve(fn _args -> {:ok, %{}} end)

              produce :user, from: :user
              delete :user
            end
          end
        end
      )
    end
  end
end
