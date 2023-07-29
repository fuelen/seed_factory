defmodule SeedFactory.SchemaTest do
  use ExUnit.Case, async: true

  @schema_example_entities %{
    office: :create_office,
    org: :create_org,
    project: :publish_project,
    draft_project: :create_draft_project,
    user: :create_user,
    profile: :create_user,
    virtual_file: :create_virtual_file
  }

  test 'SchemaExampleExtended - persisted data' do
    assert Spark.Dsl.Extension.get_persisted(SchemaExampleExtended, :entities) ==
             Map.merge(@schema_example_entities, %{conn: :build_conn})
  end

  test "persisted data - SchemaExample" do
    assert Spark.Dsl.Extension.get_persisted(SchemaExample, :entities) == @schema_example_entities

    assert Spark.Dsl.Extension.get_persisted(SchemaExample, :commands) == %{
             activate_user: %SeedFactory.Command{
               name: :activate_user,
               producing_instructions: [],
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
               ],
               deleting_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_A318D00A9A01DC9FF758958FF2E3647B/1,
               params: %{
                 finances: %SeedFactory.Parameter{
                   name: :finances,
                   params: %{
                     plan: %SeedFactory.Parameter{
                       name: :plan,
                       params: %{},
                       map: nil,
                       with_traits: nil,
                       value: :trial,
                       generate: nil,
                       entity: nil,
                       type: :value
                     }
                   },
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate: nil,
                   entity: nil,
                   type: :container
                 },
                 user: %SeedFactory.Parameter{
                   name: :user,
                   params: %{},
                   map: nil,
                   with_traits: [:pending],
                   value: nil,
                   generate: nil,
                   entity: :user,
                   type: :entity
                 }
               }
             },
             create_draft_project: %SeedFactory.Command{
               name: :create_draft_project,
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :draft_project, from: :project}
               ],
               updating_instructions: [],
               deleting_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_F9B92FE2B5FD0A57A27FB751FF0F0F04/1,
               params: %{
                 name: %SeedFactory.Parameter{
                   name: :name,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate:
                     &SchemaExample.generate_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                   entity: nil,
                   type: :generator
                 },
                 office: %SeedFactory.Parameter{
                   name: :office,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate: nil,
                   entity: :office,
                   type: :entity
                 }
               }
             },
             create_office: %SeedFactory.Command{
               name: :create_office,
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :office, from: :office}
               ],
               updating_instructions: [],
               deleting_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_DE3F3BC82EB1A0ECFC65DA3209C3BCF5/1,
               params: %{
                 name: %SeedFactory.Parameter{
                   name: :name,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate:
                     &SchemaExample.generate_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                   entity: nil,
                   type: :generator
                 },
                 org: %SeedFactory.Parameter{
                   name: :org,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate: nil,
                   entity: :org,
                   type: :entity
                 }
               }
             },
             create_org: %SeedFactory.Command{
               name: :create_org,
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :org, from: :org}
               ],
               updating_instructions: [],
               deleting_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_C9E261A7CEB6327F8844F3B180B40C30/1,
               params: %{
                 address: %SeedFactory.Parameter{
                   name: :address,
                   params: %{
                     city: %SeedFactory.Parameter{
                       name: :city,
                       params: %{},
                       map: nil,
                       with_traits: nil,
                       value: nil,
                       generate:
                         &SchemaExample.generate_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                       entity: nil,
                       type: :generator
                     },
                     country: %SeedFactory.Parameter{
                       name: :country,
                       params: %{},
                       map: nil,
                       with_traits: nil,
                       value: nil,
                       generate:
                         &SchemaExample.generate_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                       entity: nil,
                       type: :generator
                     }
                   },
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate: nil,
                   entity: nil,
                   type: :container
                 },
                 name: %SeedFactory.Parameter{
                   name: :name,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate:
                     &SchemaExample.generate_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                   entity: nil,
                   type: :generator
                 }
               }
             },
             create_user: %SeedFactory.Command{
               name: :create_user,
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :user, from: :user},
                 %SeedFactory.ProducingInstruction{entity: :profile, from: :profile}
               ],
               updating_instructions: [],
               deleting_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_B56A668B5121BBAD14A602F47827541E/1,
               params: %{
                 contacts_confirmed?: %SeedFactory.Parameter{
                   name: :contacts_confirmed?,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: false,
                   generate: nil,
                   entity: nil,
                   type: :value
                 },
                 name: %SeedFactory.Parameter{
                   name: :name,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate:
                     &SchemaExample.generate_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                   entity: nil,
                   type: :generator
                 },
                 office_id: %SeedFactory.Parameter{
                   name: :office_id,
                   params: %{},
                   map: &SchemaExample.map_0_generated_16C1099E6C1F2F2BF413FCD46A594112/1,
                   with_traits: nil,
                   value: nil,
                   generate: nil,
                   entity: :office,
                   type: :entity
                 },
                 role: %SeedFactory.Parameter{
                   name: :role,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: :normal,
                   generate: nil,
                   entity: nil,
                   type: :value
                 }
               }
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
                   params: %{},
                   map: nil,
                   with_traits: [:active, :admin],
                   value: nil,
                   generate: nil,
                   entity: :user,
                   type: :entity
                 },
                 content: %SeedFactory.Parameter{
                   name: :content,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate:
                     &SchemaExample.generate_0_generated_AE8EB7E9ED4C31FBA887B2124721814A/0,
                   entity: nil,
                   type: :generator
                 },
                 privacy: %SeedFactory.Parameter{
                   name: :privacy,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: :private,
                   generate: nil,
                   entity: nil,
                   type: :value
                 },
                 project: %SeedFactory.Parameter{
                   name: :project,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate: nil,
                   entity: :project,
                   type: :entity
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
                   params: %{},
                   map: nil,
                   with_traits: [:active],
                   value: nil,
                   generate: nil,
                   entity: :user,
                   type: :entity
                 }
               }
             },
             publish_project: %SeedFactory.Command{
               deleting_instructions: [%SeedFactory.DeletingInstruction{entity: :draft_project}],
               name: :publish_project,
               params: %{
                 project: %SeedFactory.Parameter{
                   entity: :draft_project,
                   generate: nil,
                   map: nil,
                   name: :project,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 },
                 published_by: %SeedFactory.Parameter{
                   entity: :user,
                   generate: nil,
                   map: nil,
                   name: :published_by,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: [:active]
                 },
                 expiry_date: %SeedFactory.Parameter{
                   name: :expiry_date,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate:
                     &SchemaExample.generate_0_generated_97BCB0EA065CEF28B161F312007BDF25/0,
                   entity: nil,
                   type: :generator
                 },
                 start_date: %SeedFactory.Parameter{
                   name: :start_date,
                   params: %{},
                   map: nil,
                   with_traits: nil,
                   value: nil,
                   generate:
                     &SchemaExample.generate_0_generated_C2AD3F3EB84B6CE103A970747E2E709E/0,
                   entity: nil,
                   type: :generator
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :project, from: :project}
               ],
               resolve: &SchemaExample.resolve_0_generated_71A4BAD215626E41B762AD6D43D42F61/1,
               updating_instructions: []
             },
             raise_exception: %SeedFactory.Command{
               name: :raise_exception,
               producing_instructions: [],
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
               ],
               deleting_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_9B193121A70CFA40AEB7E70819330466/1,
               params: %{}
             },
             resolve_with_error: %SeedFactory.Command{
               name: :resolve_with_error,
               producing_instructions: [],
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
               ],
               deleting_instructions: [],
               resolve: &SchemaExample.resolve_0_generated_86DFA5551DF1E7069C035938144FEFFE/1,
               params: %{}
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
                   params: %{},
                   map: nil,
                   with_traits: [:active],
                   value: nil,
                   generate: nil,
                   entity: :user,
                   type: :entity
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
              param :org, entity: :org
              resolve(fn _args -> {:ok, %{}} end)

              produce :user, from: :user
            end

            command :create_project do
              param :created_by, entity: :user

              resolve(fn _args -> {:ok, %{}} end)

              produce :project, from: :project
            end

            command :create_file do
              param :project, entity: :project
              param :created_by, entity: :user

              resolve(fn _args -> {:ok, %{}} end)

              produce :file, from: :file
            end

            command :create_org do
              param :primary_project, entity: :project

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
              param :user, entity: :user
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

            command :create_user do
              resolve(fn _args -> {:ok, %{}} end)

              produce :user, from: :user
            end

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
          defmodule MySchema8 do
            use SeedFactory.Schema

            command :create_user do
              param :user, entity: :user
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
          defmodule MySchema9 do
            use SeedFactory.Schema

            command :create_user do
              param :user, entity: :user
              resolve(fn _args -> {:ok, %{}} end)

              produce :user, from: :user
              delete :user
            end
          end
        end
      )
    end

    test "invalid command in exec step" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema10]
         root -> trait -> pending -> user:
          contains an exec step to the :create_org command which neither produces nor updates the :user entity
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema10 do
            use SeedFactory.Schema

            command :create_org do
              resolve(fn _args -> {:ok, %{}} end)

              produce :org, from: :org
            end

            command :create_user do
              param :org, entity: :org
              resolve(fn _args -> {:ok, %{}} end)

              produce :user, from: :user
            end

            trait :pending, :user do
              exec :create_org
            end
          end
        end
      )
    end

    test "defining trait for an unknown command" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema11]
         root -> trait -> pending -> org:
          unknown command :create_new_org
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema11 do
            use SeedFactory.Schema

            command :create_org do
              resolve(fn _args -> {:ok, %{}} end)

              produce :org, from: :org
            end

            trait :pending, :org do
              exec(:create_new_org)
            end
          end
        end
      )
    end

    test "defining trait for an unknown entity" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema12]
         root -> trait -> pending -> unknown:
          unknown entity
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema12 do
            use SeedFactory.Schema

            trait :pending, :unknown do
              exec(:create_org)
            end
          end
        end
      )
    end

    test "args_match is present without generate_arg" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema13]
         root -> exec:
          Option generate_args is required when args_match is specified
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema13 do
            use SeedFactory.Schema

            trait :pending, :unknown do
              exec :create_org, args_match: fn _ -> true end
            end
          end
        end
      )
    end

    test "generate_args is present without args_match" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema14]
         root -> exec:
          Option args_match is required when generate_args` is specified
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema14 do
            use SeedFactory.Schema

            trait :pending, :unknown do
              exec :create_org, generate_args: fn -> true end
            end
          end
        end
      )
    end

    test "generate_args is present wit args_pattern" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema15]
         root -> exec:
          Option args_pattern cannot be used with generate_args and args_match options
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema15 do
            use SeedFactory.Schema

            trait :pending, :unknown do
              exec :create_org, generate_args: fn -> true end, args_pattern: %{}
            end
          end
        end
      )
    end

    test "args_match is present with args_pattern" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema16]
         root -> exec:
          Option args_pattern cannot be used with generate_args and args_match options
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema16 do
            use SeedFactory.Schema

            trait :pending, :unknown do
              exec :create_org, args_match: fn _ -> true end, args_pattern: %{}
            end
          end
        end
      )
    end
  end
end
