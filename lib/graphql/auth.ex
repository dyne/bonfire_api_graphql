defmodule Bonfire.GraphQL.Auth do

  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.GraphQL
  alias Bonfire.Common.Utils

  @doc """
  Resolver for login mutation for Bonfire.GraphQL.CommonSchema
  """
  def login(_, %{email_or_username: email_or_username, password: password} = attrs, _) do
    if Utils.module_enabled?(Bonfire.Me.Accounts) do
      with {:ok, account} <- Utils.maybe_apply(Bonfire.Me.Accounts, :login, attrs) do
        user = account |> repo().maybe_preload(:accounted) |> Map.get(:accounted, []) |> hd() |> Map.get(:user, nil)
        {:ok, Map.merge(user, %{
              current_account: account,
              current_user: user,
              current_account_id: Map.get(account, :id),
              current_username: username(user)
            } ) }
      else e ->
        {:error, e}
      end
    else
      {:error, "Your app's authentication is not integrated with this GraphQL mutation."}
    end
  end

  @doc """
  Puts the account/user data in Absinthe context (runs after on `login/3` resolver)
  """
  def set_context_from_resolution(%{value: %{current_account: current_account, current_user: current_user, current_account_id: current_account_id, current_username: current_username}} = resolution, _) do
    Map.update!(
      resolution,
      :context,
      &Map.merge(&1, %{
        current_account: current_account,
        current_user: current_user,
        current_account_id: current_account_id,
        current_username: current_username
      })
    )
  end

  def set_context_from_resolution(resolution, _) do
    resolution
  end

  @doc """
  Sets session cookie based on the Absinthe context set in `set_context_from_resolution/2` (called from router's `absinthe_before_send/2` )
  """
  def set_session_from_context(conn, %Absinthe.Blueprint{execution: %{context: %{current_account_id: current_account_id} = context}}) when not is_nil(current_account_id) do
    #IO.inspect(absinthe_before_send_set_session: context)
      conn
      |>
      Plug.Conn.put_session(:current_account_id, current_account_id)
      |>
      Plug.Conn.put_session(:current_username, Map.get(context, :current_username))
  end

  def set_session_from_context(conn, _) do
    conn
  end

  @doc """
  Once authenticated, load the context based on session (called from `Bonfire.GraphQL.Plugs.GraphQLContext`)
  """
  def build_context_from_session(conn) do
    #IO.inspect(session: Plug.Conn.get_session(conn))
    #IO.inspect(assigns: conn.assigns)
    context = %{
      current_account_id: conn.assigns[:current_account_id] || Plug.Conn.get_session(conn, :current_account_id),
      current_username: conn.assigns[:current_username] || Plug.Conn.get_session(conn, :current_username),
      current_account: conn.assigns[:current_account],
      current_user: conn.assigns[:current_user]
    }

    Map.merge(context, %{ # load the user from DB here once and for all
      current_user: GraphQL.current_user(context)
    })
  end

  def user_by(username, account_id) when is_binary(username) and is_binary(account_id) do
    with {:ok, u} = Utils.maybe_apply(Bonfire.Me.Users, :by_username_and_account, [username, account_id]) do
      u
    end
  end

  def account_by(account_id) when is_binary(account_id) do
    with {:ok, a} = Utils.maybe_apply(Bonfire.Me.Accounts, :get_current, account_id) do
      a
    end
  end

  def username(%{current_user: current_user}) do
    username(current_user)
  end

  def username(user) do
    Bonfire.Common.Utils.e(user, :character, :username, nil)
  end

end
