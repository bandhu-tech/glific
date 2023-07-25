defmodule GlificWeb.StatsLive do
  @moduledoc """
  StatsLive uses phoenix live view to show current stats
  """
  use GlificWeb, :live_view

  alias Glific.Reports

  @doc false
  @spec mount(any(), any(), any()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:ok, Phoenix.LiveView.Socket.t(), Keyword.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(3000, self(), :refresh)
    end

    socket = assign_stats(socket, :init)
    {:ok, socket}
  end

  @doc false
  @spec handle_info(any(), any()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket) do
    {:noreply, assign_stats(socket, :call)}
  end

  def handle_info({:get_stats, kpi}, socket) do
    org_id = get_org_id(socket)
    {:noreply, assign(socket, kpi, Reports.get_kpi(kpi, org_id))}
  end

  @doc false
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("date_offset", %{"number" => value}, socket) do
    org_id = get_org_id(socket)
    date_offset = String.to_integer(value)
    socket = assign(socket, get_daily_data(org_id, date_offset)) |> IO.inspect(label: "updated daily data")
    {:noreply, assign(socket, :date_offset, date_offset)} |> IO.inspect(label: "assigned date offset")
  end

  @spec assign_stats(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
  defp assign_stats(socket, :init) do
    stats = Enum.map(Reports.kpi_list(), &{&1, "loading.."})

    org_id = get_org_id(socket)
    date_offset = 10

    assign(socket, Keyword.merge(stats, page_title: "Glific Dashboard"))
    |> assign(date_offset: date_offset)
    |> assign(get_chart_data(org_id, date_offset)) |> IO.inspect(label: "initial assign")
  end

  defp assign_stats(socket, :call) do
    Enum.each(Reports.kpi_list(), &send(self(), {:get_stats, &1}))
    org_id = get_org_id(socket)
    date_offset = get_date_offset(socket)
    assign(socket, get_chart_data(org_id, date_offset))
  end

  @doc false
  @spec get_org_id(Phoenix.LiveView.Socket.t()) :: non_neg_integer()
  def get_org_id(socket) do
    socket.assigns[:current_user].organization_id
  end

  @doc false
  @spec get_date_offset(Phoenix.LiveView.Socket.t()) :: non_neg_integer()
  def get_date_offset(socket) do
    socket.assigns[:date_offset]
  end

  @doc false
  @spec get_chart_data(non_neg_integer(), non_neg_integer()) :: list()
  def get_chart_data(org_id, date_offset) do
    [
      get_daily_data(org_id, date_offset),
      optin_chart_data: %{
        data: fetch_count_data(:optin_chart_data, org_id),
        labels: ["Opted In", "Opted Out", "Non Opted"]
      },
      notification_chart_data: %{
        data: fetch_count_data(:notification_chart_data, org_id),
        labels: ["Critical", "Warning", "Information"]
      },
      message_type_chart_data: %{
        data: fetch_count_data(:message_type_chart_data, org_id),
        labels: ["Inbound", "Outbound"]
      },
      broadcast_data: fetch_table_data(:broadcasts, org_id),
      broadcast_headers: ["Flow Name", "Group Name", "Started At", "Completed At"],
      contact_pie_chart_data: fetch_contact_pie_chart_data(org_id)
    ] |> List.flatten()
  end

  @doc false
  @spec get_daily_data(non_neg_integer(), non_neg_integer()) :: list()
  def get_daily_data(org_id, date_offset) do
    [
      contact_chart_data: %{
        data: fetch_date_formatted_data("contacts", org_id, date_offset),
        labels: fetch_date_labels("contacts", org_id, date_offset)
      },
      conversation_chart_data: %{
        data: fetch_date_formatted_data("messages_conversations", org_id, date_offset),
        labels: fetch_date_labels("messages_conversations", org_id, date_offset)
      }
    ] |> IO.inspect(label: "daily data")
  end

  defp fetch_table_data(:broadcasts, org_id) do
    Reports.get_broadcast_data(org_id)
  end

  @spec fetch_count_data(atom(), non_neg_integer()) :: list()
  defp fetch_count_data(:optin_chart_data, org_id) do
    [
      Reports.get_kpi(:opted_in_contacts_count, org_id),
      Reports.get_kpi(:opted_out_contacts_count, org_id),
      Reports.get_kpi(:non_opted_contacts_count, org_id)
    ]
  end

  defp fetch_count_data(:notification_chart_data, org_id) do
    [
      Reports.get_kpi(:critical_notification_count, org_id),
      Reports.get_kpi(:warning_notification_count, org_id),
      Reports.get_kpi(:information_notification_count, org_id)
    ]
  end

  defp fetch_count_data(:message_type_chart_data, org_id) do
    [
      Reports.get_kpi(:inbound_messages_count, org_id),
      Reports.get_kpi(:outbound_messages_count, org_id)
    ]
  end

  @spec fetch_date_formatted_data(String.t(), non_neg_integer(), non_neg_integer()) :: list()
  defp fetch_date_formatted_data(table_name, org_id, date_offset) do
    Reports.get_kpi_data(org_id, table_name, date_offset)
    |> Map.values()
  end

  @spec fetch_date_labels(String.t(), non_neg_integer(), non_neg_integer()) :: list()
  defp fetch_date_labels(table_name, org_id, date_offset) do
    Reports.get_kpi_data(org_id, table_name, date_offset)
    |> Map.keys()
  end

  @spec fetch_contact_pie_chart_data(non_neg_integer()) :: list()
  defp fetch_contact_pie_chart_data(org_id) do
    Reports.get_contact_data(org_id)
    |> Enum.reduce(%{data: [], labels: []}, fn [label, count], acc ->
      data = acc.data ++ [count]
      labels = acc.labels ++ [label]
      %{data: data, labels: labels}
    end)
  end
end
