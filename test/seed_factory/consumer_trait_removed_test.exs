defmodule SeedFactory.ConsumerTraitRemovedTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :audit_ticket needs a :ready ticket and a receipt, and the only receipt
    # comes from :archive_ticket, which strips :ready from the only ticket. No
    # plan can feed :audit_ticket what it asks for.
    command :create_ticket do
      resolve(fn _ -> {:ok, %{ticket: :ready_ticket}} end)

      produce :ticket
    end

    command :archive_ticket do
      param :ticket, entity: :ticket

      resolve(fn _ -> {:ok, %{ticket: :archived_ticket, receipt: :receipt1}} end)

      update :ticket
      produce :receipt
    end

    command :audit_ticket do
      param :ticket, entity: :ticket, with_traits: [:ready]
      param :receipt, entity: :receipt

      resolve(fn args ->
        send(self(), {:audited, args.ticket})
        {:ok, %{audit: :audit1}}
      end)

      produce :audit
    end

    trait :ready, :ticket do
      exec :create_ticket
    end

    trait :archived, :ticket do
      from :ready
      exec :archive_ticket
    end

    # The legal shape: :prep_f strips :tf and :use_f depends on it through :y,
    # but :seal_f, the command applying :tf, depends on :prep_f too, so the
    # removal runs before the trait is applied and :use_f reads a :tf f.
    command :create_f do
      resolve(fn _ -> {:ok, %{f: :f1}} end)

      produce :f
    end

    command :prep_f do
      param :f, entity: :f

      resolve(fn _ -> {:ok, %{f: :prepped_f, y: :y1}} end)

      update :f
      produce :y
    end

    command :seal_f do
      param :f, entity: :f
      param :y, entity: :y

      resolve(fn _ -> {:ok, %{f: :sealed_f}} end)

      update :f
    end

    command :use_f do
      param :f, entity: :f, with_traits: [:tf]
      param :y, entity: :y

      resolve(fn args -> {:ok, %{u: args.f}} end)

      produce :u
    end

    trait :tf, :f do
      exec :seal_f
    end

    trait :tx, :f do
      from :tf
      exec :prep_f
    end

    # The remover forced before the consumer by an ordering edge alone:
    # :make_e1 and :make_e2 both produce e, so :del_e has to run between them,
    # and the search orders it after :make_e1, the producer it reads. :del_e
    # strips :tm from m, which :make_e2 needs, and nothing re-applies it.
    command :make_m do
      resolve(fn _ -> {:ok, %{m: :m1}} end)

      produce :m
    end

    command :make_e1 do
      resolve(fn _ -> {:ok, %{e: :e1, left: :left1}} end)

      produce :e
      produce :left
    end

    command :del_e do
      param :e, entity: :e
      param :m, entity: :m

      resolve(fn _ -> {:ok, %{junk: :junk1, m: :stripped_m}} end)

      delete :e
      produce :junk
      update :m
    end

    command :make_e2 do
      param :m, entity: :m, with_traits: [:tm]

      resolve(fn args ->
        send(self(), {:made_e2, args.m})
        {:ok, %{e: :e2, right: :right1}}
      end)

      produce :e
      produce :right
    end

    trait :tm, :m do
      exec :make_m
    end

    trait :tmx, :m do
      from :tm
      exec :del_e
    end
  end

  use SeedFactory.Test, schema: Schema

  @message "cannot satisfy trait :ready for entity :ticket (trait required by :audit_ticket command)\n" <>
             "- command :archive_ticket, chosen for the plan, applies :archived and removes :ready"

  test "a consumer depending on the remover of its required trait fails the plan loudly",
       context do
    assert_raise SeedFactory.TraitResolutionError, @message, fn -> produce(context, :audit) end

    refute_received {:audited, _}
  end

  test "the parameters of exec are protected as the request", context do
    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :ready for entity :ticket (requested trait)\n" <>
                   "- command :archive_ticket, chosen for the plan, applies :archived and removes :ready",
                 fn -> exec(context, :audit_ticket) end

    refute_received {:audited, _}
  end

  test "an ordering edge forces the remover before the consumer as a dependency does",
       context do
    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :tm for entity :m (trait required by :make_e2 command)\n" <>
                   "- command :del_e, chosen for the plan, applies :tmx and removes :tm",
                 fn -> produce(context, [:left, :right, :junk]) end

    refute_received {:made_e2, _}
  end

  test "a remover forced before the trait's command is legal for a consumer too", context do
    context = produce(context, :u)

    assert context.u == :sealed_f
  end
end
