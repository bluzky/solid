defmodule Solid do
  @moduledoc """
  Main module to interact with Solid

  iex> Solid.parse("{{ variable }}") |> elem(1) |> Solid.render(%{ "variable" => "value" }) |> to_string
  "value"
  """
  alias Solid.{Object, Tag, Context}

  defmodule Template do
    @enforce_keys [:parsed_template]
    defstruct [:parsed_template]
  end

  defmodule TemplateError do
    defexception [:message, :line, :column, :reason, :template, :file]

    @impl true
    def exception([reason, file, line, column, template]) do
      message = """
      Error parsing file: #{file}:#{elem(line, 0)}
      Reason: #{reason}
      >>> #{template}
      """

      %__MODULE__{
        message: message,
        reason: reason,
        line: line,
        template: template,
        file: file,
        column: column
      }
    end
  end

  @doc """
  It generates the compiled template
  """
  @spec parse(String.t(), Keyword.t()) :: {:ok, %Template{}} | {:error, %TemplateError{}}
  def parse(text, opts \\ []) do
    parser = Keyword.get(opts, :parser, Solid.Parser)
    template_file = Keyword.get(opts, :template)

    case parser.parse(text) do
      {:ok, result, _, _, _, _} ->
        {:ok, %Template{parsed_template: result}}

      {:error, reason, remaining, _, {l, c} = line, col} ->
        String.slice(text, 0, c)
        |> IO.inspect()

        String.slice(text, 0, col)
        |> IO.inspect()

        [template | _] = String.split(remaining, "\n", parts: 2)
        {:error, TemplateError.exception([reason, template_file, line, col, template])}
    end
  end

  @doc """
  It generates the compiled template
  """
  @spec parse!(String.t(), Keyword.t()) :: %Template{} | no_return
  def parse!(text, opts \\ []) do
    case parse(text, opts) do
      {:ok, template} -> template
      {:error, template_error} -> raise template_error
    end
  end

  @doc """
  It renders the compiled template using a `hash` with vars

  **Options**
  - `tags`: map of custom render module for custom tag. Ex: `%{"my_tag" => MyRenderer}`
  - `file_system`: a tuple of {FileSytemModule, options}. If this option is not specified, `Solid` use `Solid.BlankFileSystem` which raise error when you use `render` tag. You can use `Solid.LocalFileSystem` or implement your own file system. Please read `Solid.FileSytem` for more detail.

  **Example**:

      fs = Solid.LocalFileSystem.new("/path/to/template/dir/")
      Solid.render(template, vars, [file_system: {Solid.LocalFileSystem, fs}])
  """
  # @spec render(any, Map.t) :: iolist
  def render(template_or_text, values, options \\ [])

  def render(%Template{parsed_template: parsed_template}, hash, options) do
    context = %Context{vars: hash}

    parsed_template
    |> render(context, options)
    |> elem(0)
  catch
    {:break_exp, partial_result, _context} ->
      partial_result

    {:continue_exp, partial_result, _context} ->
      partial_result
  end

  def render(text, context = %Context{}, options) do
    {result, context} =
      Enum.reduce(text, {[], context}, fn entry, {acc, context} ->
        try do
          {result, context} = do_render(entry, context, options)
          {[result | acc], context}
        catch
          {:break_exp, partial_result, context} ->
            throw({:break_exp, Enum.reverse([partial_result | acc]), context})

          {:continue_exp, partial_result, context} ->
            throw({:continue_exp, Enum.reverse([partial_result | acc]), context})
        end
      end)

    {Enum.reverse(result), context}
  end

  defp do_render({:text, string}, context, _options), do: {string, context}

  defp do_render({:object, object}, context, options) do
    object_text = Object.render(object, context, options)
    {object_text, context}
  end

  defp do_render({:tag, tag}, context, options) do
    render_tag(tag, context, options)
  end

  defp render_tag(tag, context, options) do
    {result, context} = Tag.eval(tag, context, options)

    if result do
      render(result, context, options)
    else
      {"", context}
    end
  end
end
