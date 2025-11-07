defmodule SeedFactory.SchemaTest do
  use ExUnit.Case, async: true

  setup do
    debug_info? = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)
    on_exit(fn -> Code.put_compiler_option(:debug_info, debug_info?) end)
    :ok
  end

  # Helper to remove __spark_metadata__ from nested structures for comparison
  defp strip_metadata(map) when is_map(map) do
    map
    |> Map.drop([:__spark_metadata__, :__struct__])
    |> Map.new(fn {k, v} -> {k, strip_metadata(v)} end)
  end

  defp strip_metadata(list) when is_list(list), do: Enum.map(list, &strip_metadata/1)
  defp strip_metadata(other), do: other

  # Helper to create regex pattern from error message with <LINE_NUMBER> placeholder
  defp error_pattern(message) do
    message
    |> String.trim_trailing()
    |> Regex.escape()
    |> String.replace("<LINE_NUMBER>", "\\d+")
    |> then(&"^#{&1}$")
    |> Regex.compile!()
  end

  # Helper to assert exception while suppressing diagnostic warnings
  defp assert_dsl_error(message, fun) do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_raise(Spark.Error.DslError, error_pattern(message), fun)
    end)
  end

  @schema_example_entities %{
    approval_process: [:start_approval_process],
    approved_candidate: [:approve_candidate, :create_approved_candidate],
    candidate_profile: [:start_approval_process, :create_approved_candidate],
    draft_project: [
      :create_draft_project,
      :import_draft_project_from_third_party_service,
      :import_draft_project_from_ftp_server
    ],
    email: [:publish_project, :suspend_user],
    files_removal_task: [:schedule_files_removal],
    imported_item_log: [
      :import_draft_project_from_third_party_service,
      :import_draft_project_from_ftp_server
    ],
    office: [:create_office],
    org: [:create_org],
    profile: [:create_pending_user, :create_active_user],
    project: [:publish_project],
    proposal: [:add_proposal_v1, :add_proposal_v2],
    task: [:create_task],
    user: [:create_pending_user, :create_active_user],
    virtual_file: [:create_virtual_file],
    integration_pipeline: [
      :bootstrap_sandbox_pipeline,
      :bootstrap_production_pipeline,
      :bootstrap_legacy_pipeline,
      :bootstrap_blocked_pipeline
    ],
    launch_announcement: [:publish_launch_announcement],
    project_quota: [:configure_project_quota]
  }

  test "SchemaExampleExtended - persisted data" do
    assert Spark.Dsl.Extension.get_persisted(SchemaExampleExtended, :entities) ==
             Map.merge(@schema_example_entities, %{conn: [:build_conn]})
  end

  test "persisted data - SchemaExample" do
    assert Spark.Dsl.Extension.get_persisted(SchemaExample, :entities) == @schema_example_entities

    actual_commands = SchemaExample |> Spark.Dsl.Extension.get_persisted(:commands)

    expected_commands = %{
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
                value: :free,
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
        required_entities: %{user: MapSet.new([:pending])},
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
        required_entities: %{draft_project: MapSet.new([])},
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
        required_entities: %{draft_project: MapSet.new([])},
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
        required_entities: %{profile: MapSet.new([]), user: MapSet.new([:suspended])},
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
        required_entities: %{approval_process: MapSet.new([])},
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
        required_entities: %{project: MapSet.new([])},
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
        required_entities: %{task: MapSet.new([])},
        resolve: &SchemaExample.resolve_0_generated_D3E8714C9FE3F744E20FB2B7E89856C4/1,
        updating_instructions: [
          %SeedFactory.UpdatingInstruction{entity: :task, from: :task}
        ]
      },
      create_active_user: %SeedFactory.Command{
        deleting_instructions: [],
        name: :create_active_user,
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
                value: :free,
                with_traits: nil
              }
            },
            type: :container,
            value: nil,
            with_traits: nil
          },
          name: %SeedFactory.Parameter{
            entity: nil,
            generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
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
        required_entities: %{office: MapSet.new([])},
        resolve: &SchemaExample.resolve_0_generated_F03B563961F14FD60C2458326365D18E/1,
        updating_instructions: []
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
        required_entities: %{},
        resolve: &SchemaExample.resolve_0_generated_A9895133DCE87707119ADFBD53DE469C/1,
        updating_instructions: []
      },
      create_draft_project: %SeedFactory.Command{
        deleting_instructions: [],
        name: :create_draft_project,
        params: %{
          name: %SeedFactory.Parameter{
            entity: nil,
            generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
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
        required_entities: %{office: MapSet.new([])},
        resolve: &SchemaExample.resolve_0_generated_2740D56C444EAB483E6E223C0EA89586/1,
        updating_instructions: []
      },
      create_office: %SeedFactory.Command{
        deleting_instructions: [],
        name: :create_office,
        params: %{
          name: %SeedFactory.Parameter{
            entity: nil,
            generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
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
        required_entities: %{org: MapSet.new([])},
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
                generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
                map: nil,
                name: :city,
                params: %{},
                type: :generator,
                value: nil,
                with_traits: nil
              },
              country: %SeedFactory.Parameter{
                entity: nil,
                generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
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
            generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
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
        required_entities: %{},
        resolve: &SchemaExample.resolve_0_generated_8EBDFE37F15A561AC04FAB5BA12B73C2/1,
        updating_instructions: []
      },
      create_task: %SeedFactory.Command{
        deleting_instructions: [],
        name: :create_task,
        params: %{
          text: %SeedFactory.Parameter{
            entity: nil,
            generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
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
        required_entities: %{},
        resolve: &SchemaExample.resolve_0_generated_0D507D35A926192FD24E8ADD63391E2D/1,
        updating_instructions: []
      },
      create_pending_user: %SeedFactory.Command{
        deleting_instructions: [],
        name: :create_pending_user,
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
            generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
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
        required_entities: %{office: MapSet.new([])},
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
            generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
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
        required_entities: %{
          project: MapSet.new([:not_expired]),
          user: MapSet.new([:active, :admin])
        },
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
        required_entities: %{user: MapSet.new([:active])},
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
        required_entities: %{email: MapSet.new([])},
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
            generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
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
        required_entities: %{office: MapSet.new([])},
        resolve: &SchemaExample.resolve_0_generated_38AB9D561752710CA46AC0BFC6D5CDBA/1,
        updating_instructions: []
      },
      import_draft_project_from_third_party_service: %SeedFactory.Command{
        deleting_instructions: [],
        name: :import_draft_project_from_third_party_service,
        params: %{
          name: %SeedFactory.Parameter{
            entity: nil,
            generate: &SchemaExample.generate_0_generated_5895C24D4750A17D9E3B5722DFA633BF/0,
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
        required_entities: %{office: MapSet.new([])},
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
        required_entities: %{task: MapSet.new([])},
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
            generate: &SchemaExample.generate_0_generated_7F99D1225460EEA808E346B442A7D5B8/0,
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
            generate: &SchemaExample.generate_0_generated_7CF4A6C502846B47087E85EAFA893284/0,
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
        required_entities: %{draft_project: MapSet.new([]), user: MapSet.new([:active])},
        resolve: &SchemaExample.resolve_0_generated_C141818E4E88F27CFC2D528EE1E2B0FF/1,
        updating_instructions: []
      },
      raise_exception: %SeedFactory.Command{
        deleting_instructions: [],
        name: :raise_exception,
        params: %{},
        producing_instructions: [],
        required_entities: %{},
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
        required_entities: %{},
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
        required_entities: %{profile: MapSet.new([:anonymized])},
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
        required_entities: %{},
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
        required_entities: %{user: MapSet.new([:active])},
        resolve: &SchemaExample.resolve_0_generated_85888B7C671514955AB26CD5F639E2F3/1,
        updating_instructions: [
          %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
        ]
      },
      move_task_to_in_review: %SeedFactory.Command{
        name: :move_task_to_in_review,
        resolve: &SchemaExample.resolve_0_generated_E21006AE7D1E787A2A1984B2F53F852C/1,
        params: %{
          task: %SeedFactory.Parameter{
            name: :task,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :task,
            with_traits: nil
          }
        },
        producing_instructions: [],
        updating_instructions: [
          %SeedFactory.UpdatingInstruction{entity: :task, from: :task}
        ],
        deleting_instructions: [],
        required_entities: %{task: MapSet.new([])}
      },
      bootstrap_blocked_pipeline: %SeedFactory.Command{
        name: :bootstrap_blocked_pipeline,
        resolve: &SchemaExample.resolve_0_generated_C08613AA81D71D19649ACD4959BCC7FD/1,
        params: %{},
        producing_instructions: [
          %SeedFactory.ProducingInstruction{
            entity: :integration_pipeline,
            from: :integration_pipeline
          }
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{}
      },
      bootstrap_legacy_pipeline: %SeedFactory.Command{
        name: :bootstrap_legacy_pipeline,
        resolve: &SchemaExample.resolve_0_generated_97BCE0A8433BAFE96A0CCFDF2DC78243/1,
        params: %{},
        producing_instructions: [
          %SeedFactory.ProducingInstruction{
            entity: :integration_pipeline,
            from: :integration_pipeline
          }
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{}
      },
      bootstrap_production_pipeline: %SeedFactory.Command{
        name: :bootstrap_production_pipeline,
        resolve: &SchemaExample.resolve_0_generated_5A6A6BD7FB8D5C7E3484AB5766FE4AFB/1,
        params: %{},
        producing_instructions: [
          %SeedFactory.ProducingInstruction{
            entity: :integration_pipeline,
            from: :integration_pipeline
          }
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{}
      },
      bootstrap_sandbox_pipeline: %SeedFactory.Command{
        name: :bootstrap_sandbox_pipeline,
        resolve: &SchemaExample.resolve_0_generated_531D13E399DD3CE104033886E87B3B8D/1,
        params: %{},
        producing_instructions: [
          %SeedFactory.ProducingInstruction{
            entity: :integration_pipeline,
            from: :integration_pipeline
          }
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{}
      },
      complete_regional_validation: %SeedFactory.Command{
        name: :complete_regional_validation,
        resolve: &SchemaExample.resolve_0_generated_410F0E884AAD26F0D3E4F6C3733DDBCB/1,
        params: %{
          integration_pipeline: %SeedFactory.Parameter{
            name: :integration_pipeline,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :integration_pipeline,
            with_traits: nil
          }
        },
        producing_instructions: [],
        updating_instructions: [
          %SeedFactory.UpdatingInstruction{
            entity: :integration_pipeline,
            from: :integration_pipeline
          }
        ],
        deleting_instructions: [],
        required_entities: %{integration_pipeline: MapSet.new([])}
      },
      configure_project_quota: %SeedFactory.Command{
        name: :configure_project_quota,
        resolve: &SchemaExample.resolve_0_generated_D2A920CA902CB9350A2C45E820AFF774/1,
        params: %{
          quota: %SeedFactory.Parameter{
            name: :quota,
            type: :value,
            value: 1000,
            map: nil,
            generate: nil,
            params: %{},
            entity: nil,
            with_traits: nil
          }
        },
        producing_instructions: [
          %SeedFactory.ProducingInstruction{entity: :project_quota, from: :project_quota}
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{}
      },
      finalize_pipeline_launch: %SeedFactory.Command{
        name: :finalize_pipeline_launch,
        resolve: &SchemaExample.resolve_0_generated_A30477274AD24466334E790BA225F9CE/1,
        params: %{
          integration_pipeline: %SeedFactory.Parameter{
            name: :integration_pipeline,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :integration_pipeline,
            with_traits: [:production_ready, :deployment_promoted]
          }
        },
        producing_instructions: [],
        updating_instructions: [
          %SeedFactory.UpdatingInstruction{
            entity: :integration_pipeline,
            from: :integration_pipeline
          }
        ],
        deleting_instructions: [],
        required_entities: %{
          integration_pipeline: MapSet.new([:production_ready, :deployment_promoted])
        }
      },
      promote_pipeline: %SeedFactory.Command{
        name: :promote_pipeline,
        resolve: &SchemaExample.resolve_0_generated_196500BCBAE4FA99543ED34D2959F739/1,
        params: %{
          integration_pipeline: %SeedFactory.Parameter{
            name: :integration_pipeline,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :integration_pipeline,
            with_traits: nil
          }
        },
        producing_instructions: [],
        updating_instructions: [
          %SeedFactory.UpdatingInstruction{
            entity: :integration_pipeline,
            from: :integration_pipeline
          }
        ],
        deleting_instructions: [],
        required_entities: %{integration_pipeline: MapSet.new([])}
      },
      publish_launch_announcement: %SeedFactory.Command{
        name: :publish_launch_announcement,
        resolve: &SchemaExample.resolve_0_generated_52B86E9701DEB46508104DCED0F94EE3/1,
        params: %{
          integration_pipeline: %SeedFactory.Parameter{
            name: :integration_pipeline,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :integration_pipeline,
            with_traits: [:production_ready, :deployment_promoted]
          }
        },
        producing_instructions: [
          %SeedFactory.ProducingInstruction{
            entity: :launch_announcement,
            from: :launch_announcement
          }
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{
          integration_pipeline: MapSet.new([:production_ready, :deployment_promoted])
        }
      },
      sign_off_compliance_from_blocked: %SeedFactory.Command{
        name: :sign_off_compliance_from_blocked,
        resolve: &SchemaExample.resolve_0_generated_4C7E344685154AF41A02863BF6D9D2CA/1,
        params: %{
          integration_pipeline: %SeedFactory.Parameter{
            name: :integration_pipeline,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :integration_pipeline,
            with_traits: nil
          }
        },
        producing_instructions: [],
        updating_instructions: [
          %SeedFactory.UpdatingInstruction{
            entity: :integration_pipeline,
            from: :integration_pipeline
          }
        ],
        deleting_instructions: [],
        required_entities: %{integration_pipeline: MapSet.new([])}
      },
      sign_off_compliance_from_legacy: %SeedFactory.Command{
        name: :sign_off_compliance_from_legacy,
        resolve: &SchemaExample.resolve_0_generated_4C7E344685154AF41A02863BF6D9D2CA/1,
        params: %{
          integration_pipeline: %SeedFactory.Parameter{
            name: :integration_pipeline,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :integration_pipeline,
            with_traits: nil
          }
        },
        producing_instructions: [],
        updating_instructions: [
          %SeedFactory.UpdatingInstruction{
            entity: :integration_pipeline,
            from: :integration_pipeline
          }
        ],
        deleting_instructions: [],
        required_entities: %{integration_pipeline: MapSet.new([])}
      }
    }

    assert strip_metadata(actual_commands) == strip_metadata(expected_commands)
  end

  describe "validations" do
    test "command without resolve arg" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> command -> action1 defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          required :resolve option not found, received options: [:name]
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            command :action1 do
            end
          end
        end
      )
    end

    test "commands with duplicated names" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> command -> action1 defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          duplicated command name
        """,
        fn ->
          defmodule MySchema do
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
      assert_dsl_error(
        """
        [SeedFactory.Command]
        root -> command -> action1 defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          at least 1 produce, update or delete directive must be set
        """,
        fn ->
          defmodule MySchema do
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
        ~r"#{Regex.escape("[SeedFactory.SchemaTest.MySchema]\nroot :\n  found dependency cycles:\n  * ")}((:create_user - :create_org - :create_project)|(:create_project - :create_user - :create_org)|(:create_org - :create_project - :create_user))$",
        fn ->
          defmodule MySchema do
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
        [SeedFactory.SchemaTest.MySchema]
        root :
          found dependency cycles:
          * :create_user
        """
        |> String.trim_trailing(),
        fn ->
          defmodule MySchema do
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
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> trait -> pending -> user defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          duplicated trait
        """,
        fn ->
          defmodule MySchema do
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
      assert_dsl_error(
        """
        [SeedFactory.Command]
        root -> command -> create_user defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          cannot apply multiple instructions on the same entity (:user)
        """,
        fn ->
          defmodule MySchema do
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

      assert_dsl_error(
        """
        [SeedFactory.Command]
        root -> command -> create_user defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          cannot apply multiple instructions on the same entity (:user)
        """,
        fn ->
          defmodule MySchema do
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
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> trait -> pending -> user defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          contains an exec step to the :create_org command which neither produces nor updates the :user entity
        """,
        fn ->
          defmodule MySchema do
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
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> trait -> pending -> org defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          unknown command :create_new_org
        """,
        fn ->
          defmodule MySchema do
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
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> trait -> pending -> unknown defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          unknown entity
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            trait :pending, :unknown do
              exec(:create_org)
            end
          end
        end
      )
    end

    test "defining trait transition with empty from list" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> trait -> invalid -> user defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          :from option cannot be an empty list
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            command :create_user do
              resolve(fn _ -> {:ok, %{user: %{id: 1}}} end)
              produce :user
            end

            trait :invalid, :user do
              from []
              exec :create_user
            end
          end
        end
      )
    end

    test "args_match is present without generate_arg" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> exec defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          Option generate_args is required when args_match is specified
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            trait :pending, :unknown do
              exec :create_org, args_match: fn _ -> true end
            end
          end
        end
      )
    end

    test "generate_args is present without args_match" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> exec defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          Option args_match is required when generate_args` is specified
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            trait :pending, :unknown do
              exec :create_org, generate_args: fn -> true end
            end
          end
        end
      )
    end

    test "generate_args is present wit args_pattern" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> exec defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          Option args_pattern cannot be used with generate_args and args_match options
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            trait :pending, :unknown do
              exec :create_org, generate_args: fn -> true end, args_pattern: %{}
            end
          end
        end
      )
    end

    test "args_match is present with args_pattern" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> exec defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          Option args_pattern cannot be used with generate_args and args_match options
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            trait :pending, :unknown do
              exec :create_org, args_match: fn _ -> true end, args_pattern: %{}
            end
          end
        end
      )
    end

    test "don't allow `nil` command name" do
      assert_dsl_error(
        """
        [SeedFactory.Command]
        root -> command -> nil defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          name of the command cannot be nil
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            command nil do
              resolve(fn _ -> {:ok, %{}} end)
            end
          end
        end
      )
    end

    test "with_traits specified for parameter with type which is not :entity" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> param -> author defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          :with_traits option can be used only if entity is specified
        """,
        fn ->
          defmodule MySchema do
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

  describe "trait transition validation" do
    test "raises when transition trait reuses a producing command" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> trait -> invalid_transition -> thing defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          trait references :create_thing via `from`, but the command produces the :thing entity. Transitions must update existing entities.
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            command :create_thing do
              resolve(fn _ -> {:ok, %{thing: %{id: 1}}} end)
              produce :thing
            end

            trait :initial, :thing do
              exec :create_thing
            end

            trait :invalid_transition, :thing do
              from :initial
              exec :create_thing
            end
          end
        end
      )
    end

    test "raises when transition trait uses a command that does not update the entity" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> trait -> invalid_transition -> thing defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          trait references :touch_thing via `from`, but the command does not update the :thing entity.
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            command :create_thing do
              resolve(fn _ -> {:ok, %{thing: %{id: 1}}} end)
              produce :thing
            end

            command :touch_thing do
              resolve(fn _ -> {:ok, %{}} end)
              delete :thing
            end

            trait :initial, :thing do
              exec :create_thing
            end

            trait :invalid_transition, :thing do
              from :initial
              exec :touch_thing
            end
          end
        end
      )
    end
  end
end
