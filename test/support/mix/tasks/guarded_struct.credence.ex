defmodule Mix.Tasks.GuardedStruct.Credence do
  @shortdoc "Checks the code with Credence's pattern rules and fails on any finding"

  @moduledoc """
  Runs [Credence](https://hex.pm/packages/credence)'s pattern rules over `lib`, `test` and `config`
  and fails when one of them finds code that works but is written the slow or roundabout way
  (`length(list) == 0`, `Enum.map/2` into `Enum.sum/1`, a `@doc` on a `defp`, ...).

      mix guarded_struct.credence

  Credence ships no task that checks a whole project, so this one reads each file and calls
  `Credence.Pattern.analyze/2`, which works on the parsed source and compiles nothing. Credence's
  semantic round is left out: it compiles every file on its own, and `mix compile
  --warnings-as-errors` already fails on the compiler warnings it looks for.

  `mix ci` runs it after `credo`. It lives in `test/support`, beside the rest of the code that
  exists only to check this library, so Credence is never a dependency of a project that uses guarded_struct;
  `cli/0` in `mix.exs` runs it in the test environment.

  ## Rules left out

    * `NoCaseTrueFalse` asks for `if`/`else` in place of `case expr do true -> ...; false -> ... end`.
      Mishka code matches on the boolean on purpose (pattern matching before `if`), so following the
      rule would turn the house style around.
  """

  use Mix.Task

  @excluded_rules [Credence.Pattern.NoCaseTrueFalse]

  @paths "{lib,test,config}/**/*.{ex,exs}"

  @impl Mix.Task
  def run(_args) do
    rules = Credence.Pattern.default_rules() -- @excluded_rules

    @paths
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(&file_issues(&1, rules))
    |> report()
  end

  defp file_issues(path, rules) do
    path
    |> File.read!()
    |> Credence.Pattern.analyze(rules: rules)
    |> Enum.map(&{path, &1})
  end

  defp report([]), do: Mix.shell().info("Credence: no issues found.")

  defp report(issues) do
    Enum.each(issues, fn {path, issue} ->
      Mix.shell().info(
        "#{path}:#{issue.meta[:line]} [#{issue.rule}] #{first_line(issue.message)}"
      )
    end)

    Mix.raise("Credence found #{length(issues)} issue(s).")
  end

  defp first_line(message), do: message |> String.split("\n", parts: 2) |> hd()
end
