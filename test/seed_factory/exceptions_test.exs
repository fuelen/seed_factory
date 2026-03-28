defmodule SeedFactory.ExceptionsTest do
  use ExUnit.Case, async: true

  describe "TraitPathNotFoundError" do
    test "format_binding when entity == binding" do
      error =
        SeedFactory.TraitPathNotFoundError.exception(
          entity: :user,
          binding: :user,
          required_traits: [:active],
          conflicting_traits: [:suspended],
          current_traits: [:pending]
        )

      assert error.message =~
               "cannot apply traits [:active] to :user,"
    end

    test "format_binding when entity != binding" do
      error =
        SeedFactory.TraitPathNotFoundError.exception(
          entity: :user,
          binding: :admin_user,
          required_traits: [:active],
          conflicting_traits: [:suspended],
          current_traits: [:pending]
        )

      assert error.message =~
               "cannot apply traits [:active] to :admin_user (entity :user),"
    end
  end

  describe "TraitRemovedByCommandError" do
    test "format_binding when entity == binding" do
      error =
        SeedFactory.TraitRemovedByCommandError.exception(
          entity: :user,
          binding: :user,
          removed_traits: [:active],
          command: :suspend_user,
          current_traits: [:suspended]
        )

      assert error.message =~
               "cannot apply traits [:active] to :user because"
    end

    test "format_binding when entity != binding" do
      error =
        SeedFactory.TraitRemovedByCommandError.exception(
          entity: :user,
          binding: :admin_user,
          removed_traits: [:active],
          command: :suspend_user,
          current_traits: [:suspended]
        )

      assert error.message =~
               "cannot apply traits [:active] to :admin_user (entity :user) because"
    end
  end

  describe "ExecError" do
    test "message with nil execution_plan, empty trails and empty current_traits" do
      error = %SeedFactory.ExecError{
        command: :some_command,
        exception: nil,
        error: :some_error,
        stacktrace: nil,
        execution_plan: nil,
        trails: %{},
        current_traits: %{}
      }

      assert Exception.message(error) ==
               "unable to execute :some_command command: :some_error"
    end

    test "message with execution_plan but empty trails and empty current_traits" do
      error = %SeedFactory.ExecError{
        command: :some_command,
        exception: nil,
        error: :some_error,
        stacktrace: nil,
        execution_plan: [{:some_command, :failed}],
        trails: %{},
        current_traits: %{}
      }

      assert Exception.message(error) ==
               """
               unable to execute :some_command command: :some_error

               Execution plan:
                 ✖ :some_command\
               """
    end
  end
end
