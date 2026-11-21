defmodule FrontierWeb.Layouts do
  @moduledoc """
  The document shell the paper is printed in.

  `root.html.heex` is the whole frame: type stack, fonts, stylesheet. Page
  templates put the masthead, stories and colophon inside it.
  """
  use FrontierWeb, :html

  embed_templates "layouts/*"
end
