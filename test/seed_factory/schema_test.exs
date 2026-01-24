defmodule SeedFactory.SchemaTest do
  use ExUnit.Case, async: true

  setup do
    debug_info? = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)
    on_exit(fn -> Code.put_compiler_option(:debug_info, debug_info?) end)
    :ok
  end

  # Helper to normalize nested structures for comparison by removing internal fields
  defp strip_metadata(map) when is_map(map) do
    map
    # __spark_metadata__, __struct__ - internal Spark fields
    # resolve - function reference with hash based on line number, not useful to compare
    |> Map.drop([:__spark_metadata__, :__struct__, :resolve])
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
    award: [:grant_award, :nominate_award, :direct_award],
    candidate_profile: [
      :start_approval_process,
      :create_candidate_profile,
      :create_approved_candidate
    ],
    candidate_welcome_notification: [:send_welcome_to_candidate, :send_welcome_to_candidate_v2],
    ceremony: [:create_ceremony],
    document: [:create_document, :create_document_for_verified_profile],
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
    nomination: [:grant_award, :nominate_award],
    office: [:create_office],
    org: [:create_org],
    prize: [:direct_award, :earn_prize],
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
    project_quota: [:configure_project_quota],
    widget: [:create_widget, :create_widget_and_bundle],
    widget_bundle: [:create_widget_and_bundle, :create_widget_bundle_only]
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
        updating_instructions: []
      },
      raise_exception: %SeedFactory.Command{
        deleting_instructions: [],
        name: :raise_exception,
        params: %{},
        producing_instructions: [],
        required_entities: %{},
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
        updating_instructions: []
      },
      send_welcome_to_candidate: %SeedFactory.Command{
        deleting_instructions: [],
        name: :send_welcome_to_candidate,
        params: %{
          candidate_profile: %SeedFactory.Parameter{
            entity: :candidate_profile,
            generate: nil,
            map: nil,
            name: :candidate_profile,
            params: %{},
            type: :entity,
            value: nil,
            with_traits: nil
          }
        },
        producing_instructions: [
          %SeedFactory.ProducingInstruction{
            entity: :candidate_welcome_notification,
            from: :candidate_welcome_notification
          }
        ],
        required_entities: %{candidate_profile: MapSet.new([])},
        updating_instructions: []
      },
      send_welcome_to_candidate_v2: %SeedFactory.Command{
        deleting_instructions: [],
        name: :send_welcome_to_candidate_v2,
        params: %{
          candidate_profile: %SeedFactory.Parameter{
            entity: :candidate_profile,
            generate: nil,
            map: nil,
            name: :candidate_profile,
            params: %{},
            type: :entity,
            value: nil,
            with_traits: nil
          }
        },
        producing_instructions: [
          %SeedFactory.ProducingInstruction{
            entity: :candidate_welcome_notification,
            from: :candidate_welcome_notification
          }
        ],
        required_entities: %{candidate_profile: MapSet.new([])},
        updating_instructions: []
      },
      create_candidate_profile: %SeedFactory.Command{
        deleting_instructions: [],
        name: :create_candidate_profile,
        params: %{},
        producing_instructions: [
          %SeedFactory.ProducingInstruction{
            entity: :candidate_profile,
            from: :candidate_profile
          }
        ],
        required_entities: %{},
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
        updating_instructions: [
          %SeedFactory.UpdatingInstruction{entity: :user, from: :user}
        ]
      },
      move_task_to_in_review: %SeedFactory.Command{
        name: :move_task_to_in_review,
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
      # Regression test commands for :is_subset bug
      grant_award: %SeedFactory.Command{
        name: :grant_award,
        params: %{},
        producing_instructions: [
          %SeedFactory.ProducingInstruction{entity: :award, from: :award},
          %SeedFactory.ProducingInstruction{entity: :nomination, from: :nomination}
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{}
      },
      nominate_award: %SeedFactory.Command{
        name: :nominate_award,
        params: %{},
        producing_instructions: [
          %SeedFactory.ProducingInstruction{entity: :award, from: :award},
          %SeedFactory.ProducingInstruction{entity: :nomination, from: :nomination}
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{}
      },
      create_ceremony: %SeedFactory.Command{
        name: :create_ceremony,
        params: %{
          _award: %SeedFactory.Parameter{
            name: :_award,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :award,
            with_traits: nil
          }
        },
        producing_instructions: [
          %SeedFactory.ProducingInstruction{entity: :ceremony, from: :ceremony}
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{award: MapSet.new([])}
      },
      direct_award: %SeedFactory.Command{
        name: :direct_award,
        params: %{
          _ceremony: %SeedFactory.Parameter{
            name: :_ceremony,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :ceremony,
            with_traits: nil
          }
        },
        producing_instructions: [
          %SeedFactory.ProducingInstruction{entity: :award, from: :award},
          %SeedFactory.ProducingInstruction{entity: :prize, from: :prize}
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{ceremony: MapSet.new([])}
      },
      earn_prize: %SeedFactory.Command{
        name: :earn_prize,
        params: %{
          _nomination: %SeedFactory.Parameter{
            name: :_nomination,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :nomination,
            with_traits: nil
          }
        },
        producing_instructions: [%SeedFactory.ProducingInstruction{entity: :prize, from: :prize}],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{nomination: MapSet.new([])}
      },
      create_document: %SeedFactory.Command{
        name: :create_document,
        params: %{
          profile: %SeedFactory.Parameter{
            name: :profile,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :profile,
            with_traits: nil
          }
        },
        producing_instructions: [
          %SeedFactory.ProducingInstruction{entity: :document, from: :document}
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{profile: MapSet.new([])}
      },
      create_document_for_verified_profile: %SeedFactory.Command{
        name: :create_document_for_verified_profile,
        params: %{
          profile: %SeedFactory.Parameter{
            name: :profile,
            type: :entity,
            value: nil,
            map: nil,
            generate: nil,
            params: %{},
            entity: :profile,
            with_traits: [:contacts_confirmed]
          }
        },
        producing_instructions: [
          %SeedFactory.ProducingInstruction{entity: :document, from: :document}
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{profile: MapSet.new([:contacts_confirmed])}
      },
      create_widget: %SeedFactory.Command{
        name: :create_widget,
        params: %{},
        producing_instructions: [
          %SeedFactory.ProducingInstruction{entity: :widget, from: :widget}
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{}
      },
      create_widget_and_bundle: %SeedFactory.Command{
        name: :create_widget_and_bundle,
        params: %{},
        producing_instructions: [
          %SeedFactory.ProducingInstruction{entity: :widget, from: :widget},
          %SeedFactory.ProducingInstruction{entity: :widget_bundle, from: :widget_bundle}
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{}
      },
      create_widget_bundle_only: %SeedFactory.Command{
        name: :create_widget_bundle_only,
        params: %{},
        producing_instructions: [
          %SeedFactory.ProducingInstruction{entity: :widget_bundle, from: :widget_bundle}
        ],
        updating_instructions: [],
        deleting_instructions: [],
        required_entities: %{}
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

    test "raises when from references a non-existent trait" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> trait -> advanced -> thing defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          unknown trait :nonexistent_trait in `from` option
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            command :create_thing do
              resolve(fn _ -> {:ok, %{thing: %{id: 1}}} end)
              produce :thing
            end

            command :upgrade_thing do
              param :thing, entity: :thing
              resolve(fn _ -> {:ok, %{thing: %{id: 1}}} end)
              update :thing
            end

            trait :initial, :thing do
              exec :create_thing
            end

            trait :advanced, :thing do
              from :nonexistent_trait
              exec :upgrade_thing
            end
          end
        end
      )
    end

    test "raises when from references a trait from different entity" do
      assert_dsl_error(
        """
        [SeedFactory.SchemaTest.MySchema]
        root -> trait -> thing_advanced -> thing defined in test/seed_factory/schema_test.exs:<LINE_NUMBER>::
          trait :other_initial in `from` option belongs to entity :other, not :thing
        """,
        fn ->
          defmodule MySchema do
            use SeedFactory.Schema

            command :create_thing do
              resolve(fn _ -> {:ok, %{thing: %{id: 1}}} end)
              produce :thing
            end

            command :create_other do
              resolve(fn _ -> {:ok, %{other: %{id: 1}}} end)
              produce :other
            end

            command :upgrade_thing do
              param :thing, entity: :thing
              resolve(fn _ -> {:ok, %{thing: %{id: 1}}} end)
              update :thing
            end

            trait :thing_initial, :thing do
              exec :create_thing
            end

            trait :other_initial, :other do
              exec :create_other
            end

            trait :thing_advanced, :thing do
              from :other_initial
              exec :upgrade_thing
            end
          end
        end
      )
    end
  end
end
