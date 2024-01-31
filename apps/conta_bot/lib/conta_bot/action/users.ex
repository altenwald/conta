defmodule ContaBot.Action.Users do
  use ContaBot.Action

  def granted_user?(username) do
    username in list_users()
  end

  def list_users do
    Application.get_env(:conta_bot, :granted_users, [])
  end

  def add_user(username) do
    granted_users =
      list_users()
      |> MapSet.new()
      |> MapSet.put(username)
      |> MapSet.to_list()

    Application.put_env(:conta_bot, :granted_users, granted_users)
  end

  def remove_user(username) do
    granted_users = List.delete(list_users(), username)
    Application.put_env(:conta_bot, :granted_users, granted_users)
  end

  @impl ContaBot.Action
  def handle(:init, context) do
    options = [
      {"Add", "users add"},
      {"Remove", "users remove"},
      {"List", "users list"}
    ]

    extra = [{"Cancel", "users cancel"}]
    answer_select(context, "What action do you want to perform?", options, extra)
  end

  def handle({:callback, "add"}, context) do
    answer_me(context, "Who do you want to invite? (write its username without @)")
  end

  def handle({:text, username}, context) do
    add_user(username)
    answer(context, "username *#{escape_markdown(username)}* added", parse_mode: "MarkdownV2")
  end

  def handle({:callback, "remove"}, context) do
    options =
      for user <- list_users() do
        {"Remove @#{user}", "users remove #{user}"}
      end

    extra = [{"Cancel", "users cancel"}]

    context
    |> delete_callback()
    |> answer_select("Who user do you want to remove?", options, extra)
  end

  def handle({:callback, "remove " <> username}, context) do
    remove_user(username)

    context
    |> delete_callback()
    |> answer("Username removed successfully.")
  end

  def handle({:callback, "list"}, context) do
    output =
      Enum.map_join(list_users(), "\n", fn user ->
        "\\- \\@#{escape_markdown(user)}"
      end)

    context
    |> delete_callback()
    |> answer(output, parse_mode: "MarkdownV2")
  end

  def handle({:callback, "cancel"}, context) do
    delete_callback(context)
  end
end
