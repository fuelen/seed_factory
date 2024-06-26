defmodule SeedFactory.SchemaTest do
  use ExUnit.Case, async: true

  @schema_example_entities %{
    draft_project: [
      :create_draft_project,
      :import_draft_project_from_third_party_service,
      :import_draft_project_from_ftp_server
    ],
    email: [:publish_project, :suspend_user],
    office: [:create_office],
    org: [:create_org],
    profile: [:create_user],
    project: [:publish_project],
    user: [:create_user],
    virtual_file: [:create_virtual_file],
    files_removal_task: [:schedule_files_removal],
    proposal: [:add_proposal_v1, :add_proposal_v2],
    imported_item_log: [
      :import_draft_project_from_third_party_service,
      :import_draft_project_from_ftp_server
    ],
    approval_process: [:start_approval_process],
    approved_candidate: [:approve_candidate, :create_approved_candidate],
    candidate_profile: [:start_approval_process, :create_approved_candidate],
    task: [:create_task]
  }

  test "SchemaExampleExtended - persisted data" do
    assert Spark.Dsl.Extension.get_persisted(SchemaExampleExtended, :entities) ==
             Map.merge(@schema_example_entities, %{conn: [:build_conn]})
  end

  test "persisted data - SchemaExample" do
    assert Spark.Dsl.Extension.get_persisted(SchemaExample, :entities) == @schema_example_entities

    assert Spark.Dsl.Extension.get_persisted(SchemaExample, :commands) == %{
             activate_user: %SeedFactory.Command{
               deleting_instructions: [],
               name: :activate_user,
               params: %{
                 finances: %SeedFactory.Parameter{
                   entity: nil,
                   generate: nil,
                   map: nil,
                   name: :finances,
                   params: %{
                     plan: %SeedFactory.Parameter{
                       entity: nil,
                       generate: nil,
                       map: nil,
                       name: :plan,
                       params: %{},
                       type: :value,
                       value: :trial,
                       with_traits: nil
                     }
                   },
                   type: :container,
                   value: nil,
                   with_traits: nil
                 },
                 user: %SeedFactory.Parameter{
                   entity: :user,
                   generate: nil,
                   map: nil,
                   name: :user,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: [:pending]
                 }
               },
               producing_instructions: [],
               required_entities: MapSet.new([:user]),
               resolve: &SchemaExample.resolve_0_generated_C17C97BAADD6E3D44133EA735E723E9A/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
               ]
             },
             add_proposal_v1: %SeedFactory.Command{
               deleting_instructions: [],
               name: :add_proposal_v1,
               params: %{
                 draft_project: %SeedFactory.Parameter{
                   entity: :draft_project,
                   generate: nil,
                   map: nil,
                   name: :draft_project,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :proposal, from: :proposal}
               ],
               required_entities: MapSet.new([:draft_project]),
               resolve: &SchemaExample.resolve_0_generated_27304FE0319036410B6571AA890ED703/1,
               updating_instructions: []
             },
             add_proposal_v2: %SeedFactory.Command{
               deleting_instructions: [],
               name: :add_proposal_v2,
               params: %{
                 draft_project: %SeedFactory.Parameter{
                   entity: :draft_project,
                   generate: nil,
                   map: nil,
                   name: :draft_project,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :proposal, from: :proposal}
               ],
               required_entities: MapSet.new([:draft_project]),
               resolve: &SchemaExample.resolve_0_generated_760F3AAE84A314262EE1616EC1583D2F/1,
               updating_instructions: []
             },
             anonymize_profile_of_suspended_user: %SeedFactory.Command{
               deleting_instructions: [],
               name: :anonymize_profile_of_suspended_user,
               params: %{
                 profile: %SeedFactory.Parameter{
                   entity: :profile,
                   generate: nil,
                   map: nil,
                   name: :profile,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 },
                 user: %SeedFactory.Parameter{
                   entity: :user,
                   generate: nil,
                   map: nil,
                   name: :user,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: [:suspended]
                 }
               },
               producing_instructions: [],
               required_entities: MapSet.new([:profile, :user]),
               resolve: &SchemaExample.resolve_0_generated_2F21AB2A2BABAECF79F24982211F6ED0/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :profile, from: :profile}
               ]
             },
             approve_candidate: %SeedFactory.Command{
               deleting_instructions: [],
               name: :approve_candidate,
               params: %{
                 approval_process: %SeedFactory.Parameter{
                   entity: :approval_process,
                   generate: nil,
                   map: nil,
                   name: :approval_process,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{
                   entity: :approved_candidate,
                   from: :approved_candidate
                 }
               ],
               required_entities: MapSet.new([:approval_process]),
               resolve: &SchemaExample.resolve_0_generated_224A074C182B8C840AB88365EA6AD318/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{
                   entity: :approval_process,
                   from: :approval_process
                 }
               ]
             },
             archive_project: %SeedFactory.Command{
               deleting_instructions: [],
               name: :archive_project,
               params: %{
                 project: %SeedFactory.Parameter{
                   entity: :project,
                   generate: nil,
                   map: nil,
                   name: :project,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [],
               required_entities: MapSet.new([:project]),
               resolve: &SchemaExample.resolve_0_generated_C5D5A1080411FF3BC4635FE37A406122/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :project, from: :project}
               ]
             },
             complete_task: %SeedFactory.Command{
               deleting_instructions: [],
               name: :complete_task,
               params: %{
                 task: %SeedFactory.Parameter{
                   entity: :task,
                   generate: nil,
                   map: nil,
                   name: :task,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [],
               required_entities: MapSet.new([:task]),
               resolve: &SchemaExample.resolve_0_generated_D3E8714C9FE3F744E20FB2B7E89856C4/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :task, from: :task}
               ]
             },
             create_approved_candidate: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_approved_candidate,
               params: %{},
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{
                   entity: :candidate_profile,
                   from: :candidate_profile
                 },
                 %SeedFactory.ProducingInstruction{
                   entity: :approved_candidate,
                   from: :approved_candidate
                 }
               ],
               required_entities: MapSet.new([]),
               resolve: &SchemaExample.resolve_0_generated_A9895133DCE87707119ADFBD53DE469C/1,
               updating_instructions: []
             },
             create_draft_project: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_draft_project,
               params: %{
                 name: %SeedFactory.Parameter{
                   entity: nil,
                   generate:
                     &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                   map: nil,
                   name: :name,
                   params: %{},
                   type: :generator,
                   value: nil,
                   with_traits: nil
                 },
                 office: %SeedFactory.Parameter{
                   entity: :office,
                   generate: nil,
                   map: nil,
                   name: :office,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :draft_project, from: :project}
               ],
               required_entities: MapSet.new([:office]),
               resolve: &SchemaExample.resolve_0_generated_2740D56C444EAB483E6E223C0EA89586/1,
               updating_instructions: []
             },
             create_office: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_office,
               params: %{
                 name: %SeedFactory.Parameter{
                   entity: nil,
                   generate:
                     &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                   map: nil,
                   name: :name,
                   params: %{},
                   type: :generator,
                   value: nil,
                   with_traits: nil
                 },
                 org: %SeedFactory.Parameter{
                   entity: :org,
                   generate: nil,
                   map: nil,
                   name: :org,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :office, from: :office}
               ],
               required_entities: MapSet.new([:org]),
               resolve: &SchemaExample.resolve_0_generated_473AAE83EF4BBE14B6B0B4B415D9251A/1,
               updating_instructions: []
             },
             create_org: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_org,
               params: %{
                 address: %SeedFactory.Parameter{
                   entity: nil,
                   generate: nil,
                   map: nil,
                   name: :address,
                   params: %{
                     city: %SeedFactory.Parameter{
                       entity: nil,
                       generate:
                         &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                       map: nil,
                       name: :city,
                       params: %{},
                       type: :generator,
                       value: nil,
                       with_traits: nil
                     },
                     country: %SeedFactory.Parameter{
                       entity: nil,
                       generate:
                         &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                       map: nil,
                       name: :country,
                       params: %{},
                       type: :generator,
                       value: nil,
                       with_traits: nil
                     }
                   },
                   type: :container,
                   value: nil,
                   with_traits: nil
                 },
                 name: %SeedFactory.Parameter{
                   entity: nil,
                   generate:
                     &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                   map: nil,
                   name: :name,
                   params: %{},
                   type: :generator,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :org, from: :org}
               ],
               required_entities: MapSet.new([]),
               resolve: &SchemaExample.resolve_0_generated_8EBDFE37F15A561AC04FAB5BA12B73C2/1,
               updating_instructions: []
             },
             create_task: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_task,
               params: %{
                 text: %SeedFactory.Parameter{
                   entity: nil,
                   generate:
                     &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                   map: nil,
                   name: :text,
                   params: %{},
                   type: :generator,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :task, from: :task}
               ],
               required_entities: MapSet.new([]),
               resolve: &SchemaExample.resolve_0_generated_0D507D35A926192FD24E8ADD63391E2D/1,
               updating_instructions: []
             },
             create_user: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_user,
               params: %{
                 contacts_confirmed?: %SeedFactory.Parameter{
                   entity: nil,
                   generate: nil,
                   map: nil,
                   name: :contacts_confirmed?,
                   params: %{},
                   type: :value,
                   value: false,
                   with_traits: nil
                 },
                 name: %SeedFactory.Parameter{
                   entity: nil,
                   generate:
                     &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                   map: nil,
                   name: :name,
                   params: %{},
                   type: :generator,
                   value: nil,
                   with_traits: nil
                 },
                 office_id: %SeedFactory.Parameter{
                   entity: :office,
                   generate: nil,
                   map: &SchemaExample.map_0_generated_3FF8BB7A86AA4480EFAD42A6E4A70BB4/1,
                   name: :office_id,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 },
                 role: %SeedFactory.Parameter{
                   entity: nil,
                   generate: nil,
                   map: nil,
                   name: :role,
                   params: %{},
                   type: :value,
                   value: :normal,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :user, from: :user},
                 %SeedFactory.ProducingInstruction{entity: :profile, from: :profile}
               ],
               required_entities: MapSet.new([:office]),
               resolve: &SchemaExample.resolve_0_generated_9AC210B59D8F5815BEC1F491294AC2DC/1,
               updating_instructions: []
             },
             create_virtual_file: %SeedFactory.Command{
               deleting_instructions: [],
               name: :create_virtual_file,
               params: %{
                 author: %SeedFactory.Parameter{
                   entity: :user,
                   generate: nil,
                   map: nil,
                   name: :author,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: [:active, :admin]
                 },
                 content: %SeedFactory.Parameter{
                   entity: nil,
                   generate:
                     &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                   map: nil,
                   name: :content,
                   params: %{},
                   type: :generator,
                   value: nil,
                   with_traits: nil
                 },
                 privacy: %SeedFactory.Parameter{
                   entity: nil,
                   generate: nil,
                   map: nil,
                   name: :privacy,
                   params: %{},
                   type: :value,
                   value: :private,
                   with_traits: nil
                 },
                 project: %SeedFactory.Parameter{
                   entity: :project,
                   generate: nil,
                   map: nil,
                   name: :project,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: [:not_expired]
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :virtual_file, from: :file}
               ],
               required_entities: MapSet.new([:user, :project]),
               resolve: &SchemaExample.resolve_0_generated_CCCB3F865ADE169901D82CC5FEFF48D5/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :project, from: :project}
               ]
             },
             delete_user: %SeedFactory.Command{
               deleting_instructions: [%SeedFactory.DeletingInstruction{entity: :user}],
               name: :delete_user,
               params: %{
                 user: %SeedFactory.Parameter{
                   entity: :user,
                   generate: nil,
                   map: nil,
                   name: :user,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: [:active]
                 }
               },
               producing_instructions: [],
               required_entities: MapSet.new([:user]),
               resolve: &SchemaExample.resolve_0_generated_F67D69DD4258B25927201B14AD7C8876/1,
               updating_instructions: []
             },
             deliver_email: %SeedFactory.Command{
               deleting_instructions: [],
               name: :deliver_email,
               params: %{
                 email: %SeedFactory.Parameter{
                   entity: :email,
                   generate: nil,
                   map: nil,
                   name: :email,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [],
               required_entities: MapSet.new([:email]),
               resolve: &SchemaExample.resolve_0_generated_EAE9DEB149823F722DFFBC280AF6F0FC/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :email, from: :email}
               ]
             },
             import_draft_project_from_ftp_server: %SeedFactory.Command{
               deleting_instructions: [],
               name: :import_draft_project_from_ftp_server,
               params: %{
                 name: %SeedFactory.Parameter{
                   entity: nil,
                   generate:
                     &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                   map: nil,
                   name: :name,
                   params: %{},
                   type: :generator,
                   value: nil,
                   with_traits: nil
                 },
                 office: %SeedFactory.Parameter{
                   entity: :office,
                   generate: nil,
                   map: nil,
                   name: :office,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :draft_project, from: :project},
                 %SeedFactory.ProducingInstruction{
                   entity: :imported_item_log,
                   from: :imported_item_log
                 }
               ],
               required_entities: MapSet.new([:office]),
               resolve: &SchemaExample.resolve_0_generated_38AB9D561752710CA46AC0BFC6D5CDBA/1,
               updating_instructions: []
             },
             import_draft_project_from_third_party_service: %SeedFactory.Command{
               deleting_instructions: [],
               name: :import_draft_project_from_third_party_service,
               params: %{
                 name: %SeedFactory.Parameter{
                   entity: nil,
                   generate:
                     &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                   map: nil,
                   name: :name,
                   params: %{},
                   type: :generator,
                   value: nil,
                   with_traits: nil
                 },
                 office: %SeedFactory.Parameter{
                   entity: :office,
                   generate: nil,
                   map: nil,
                   name: :office,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :draft_project, from: :project},
                 %SeedFactory.ProducingInstruction{
                   entity: :imported_item_log,
                   from: :imported_item_log
                 }
               ],
               required_entities: MapSet.new([:office]),
               resolve: &SchemaExample.resolve_0_generated_4AB4B53C6AC081BFDEC63D39CF58ED2E/1,
               updating_instructions: []
             },
             move_task_to_in_progress: %SeedFactory.Command{
               deleting_instructions: [],
               name: :move_task_to_in_progress,
               params: %{
                 task: %SeedFactory.Parameter{
                   entity: :task,
                   generate: nil,
                   map: nil,
                   name: :task,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [],
               required_entities: MapSet.new([:task]),
               resolve: &SchemaExample.resolve_0_generated_FCA220C52D67D7C19C1604D0CA004185/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :task, from: :task}
               ]
             },
             publish_project: %SeedFactory.Command{
               deleting_instructions: [%SeedFactory.DeletingInstruction{entity: :draft_project}],
               name: :publish_project,
               params: %{
                 expiry_date: %SeedFactory.Parameter{
                   entity: nil,
                   generate:
                     &SchemaExample.generate_0_generated_7F99D1225460EEA808E346B442A7D5B8/0,
                   map: nil,
                   name: :expiry_date,
                   params: %{},
                   type: :generator,
                   value: nil,
                   with_traits: nil
                 },
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
                 start_date: %SeedFactory.Parameter{
                   entity: nil,
                   generate:
                     &SchemaExample.generate_0_generated_7CF4A6C502846B47087E85EAFA893284/0,
                   map: nil,
                   name: :start_date,
                   params: %{},
                   type: :generator,
                   value: nil,
                   with_traits: nil
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :project, from: :project},
                 %SeedFactory.ProducingInstruction{entity: :email, from: :email}
               ],
               required_entities: MapSet.new([:user, :draft_project]),
               resolve: &SchemaExample.resolve_0_generated_C141818E4E88F27CFC2D528EE1E2B0FF/1,
               updating_instructions: []
             },
             raise_exception: %SeedFactory.Command{
               deleting_instructions: [],
               name: :raise_exception,
               params: %{},
               producing_instructions: [],
               required_entities: MapSet.new([]),
               resolve: &SchemaExample.resolve_0_generated_719F75E74239275E263426292AF0551F/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
               ]
             },
             resolve_with_error: %SeedFactory.Command{
               deleting_instructions: [],
               name: :resolve_with_error,
               params: %{},
               producing_instructions: [],
               required_entities: MapSet.new([]),
               resolve: &SchemaExample.resolve_0_generated_0E0E10888E2AE53D322BB8BC68C9F05F/1,
               updating_instructions: [
                 %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
               ]
             },
             schedule_files_removal: %SeedFactory.Command{
               deleting_instructions: [],
               name: :schedule_files_removal,
               params: %{
                 profile: %SeedFactory.Parameter{
                   entity: :profile,
                   generate: nil,
                   map: nil,
                   name: :profile,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: [:anonymized]
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :files_removal_task, from: :task}
               ],
               required_entities: MapSet.new([:profile]),
               resolve: &SchemaExample.resolve_0_generated_469E6B2E479D62A90FAB295422BE12C4/1,
               updating_instructions: []
             },
             start_approval_process: %SeedFactory.Command{
               deleting_instructions: [],
               name: :start_approval_process,
               params: %{},
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{
                   entity: :approval_process,
                   from: :approval_process
                 },
                 %SeedFactory.ProducingInstruction{
                   entity: :candidate_profile,
                   from: :candidate_profile
                 }
               ],
               required_entities: MapSet.new([]),
               resolve: &SchemaExample.resolve_0_generated_7A4838E0C452DEA4E0FE3F06EE16AF6F/1,
               updating_instructions: []
             },
             suspend_user: %SeedFactory.Command{
               deleting_instructions: [],
               name: :suspend_user,
               params: %{
                 user: %SeedFactory.Parameter{
                   entity: :user,
                   generate: nil,
                   map: nil,
                   name: :user,
                   params: %{},
                   type: :entity,
                   value: nil,
                   with_traits: [:active]
                 }
               },
               producing_instructions: [
                 %SeedFactory.ProducingInstruction{entity: :email, from: :email}
               ],
               required_entities: MapSet.new([:user]),
               resolve: &SchemaExample.resolve_0_generated_85888B7C671514955AB26CD5F639E2F3/1,
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

    test "don't allow `nil` command name" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.Command]
         root -> command -> nil:
          name of the command cannot be nil
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema17 do
            use SeedFactory.Schema

            command nil do
              resolve(fn _ -> {:ok, %{}} end)
            end
          end
        end
      )
    end

    test "with_traits specified for parameter with type which is not :entity" do
      assert_raise(
        Spark.Error.DslError,
        """
        [SeedFactory.SchemaTest.MySchema18]
         root -> param -> author:
          :with_traits option can be used only if entity is specified
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema18 do
            use SeedFactory.Schema

            command :create_project do
              param :author, with_traits: [:active]
              resolve(fn _ -> {:ok, %{}} end)
            end
          end
        end
      )
    end
  end
end
