defmodule GlificWeb.StatsLive do
  @moduledoc """
  StatsLive uses phoenix live view to show current stats
  """
  use GlificWeb, :live_view

  alias Glific.Reports
  alias Contex.Plot

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

  @spec assign_stats(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
  defp assign_stats(socket, :init) do
    stats = Enum.map(Reports.kpi_list(), &{&1, "loading.."})

    org_id = get_org_id(socket)

    assign(socket, Keyword.merge(stats, page_title: "Glific Dashboard"))
    |> assign(get_chart_data(org_id))
    |> assign_dataset() |> IO.inspect(label: "dataset")
    |> assign_chart() |> IO.inspect(label: "chart")
    |> assign_chart_svg() |> IO.inspect(label: "svg")
  end

  defp assign_stats(socket, :call) do
    Enum.each(Reports.kpi_list(), &send(self(), {:get_stats, &1}))
    org_id = get_org_id(socket)
    assign(socket, get_chart_data(org_id))
  end

  def assign_dataset(
    %{assigns: %{
      contact_chart_data: contact_chart_data,
      conversation_chart_data: conversation_chart_data}
    } = socket) do
      socket
      |> assign(
        :contact_dataset,
        make_bar_chart_dataset(contact_chart_data)
      )
      |> assign(
        :conversation_dataset,
        make_bar_chart_dataset(conversation_chart_data)
      )
  end

  defp make_bar_chart_dataset(data) do
    Contex.Dataset.new(data)
  end

  @doc false
  @spec get_org_id(Phoenix.LiveView.Socket.t()) :: non_neg_integer()
  def get_org_id(socket) do
    socket.assigns[:current_user].organization_id
  end

  #GlificWeb.StatsLive.fetch_date_formatted_data("contacts", 1)
  @doc false
  @spec get_chart_data(non_neg_integer()) :: list()
  def get_chart_data(org_id) do
    [
      contact_chart_data:  Reports.get_kpi_data_new(org_id, "contacts"),
      conversation_chart_data: Reports.get_kpi_data_new(org_id, "messages_conversations"),
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
    ]
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

  @spec fetch_date_formatted_data(String.t(), non_neg_integer()) :: list()
  def fetch_date_formatted_data(table_name, org_id) do
    Reports.get_kpi_data(org_id, table_name)
    |> Map.values()
  end

  @spec fetch_date_labels(String.t(), non_neg_integer()) :: list()
  defp fetch_date_labels(table_name, org_id) do
    Reports.get_kpi_data(org_id, table_name)
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

  #def update(assigns, socket) do
  #  {:ok,
   # socket
   # |> assign(assigns)
   # |> assign_chart_data()
   # |> assign_dataset()
   # |> assign_chart()
    #|> assign_chart_svg()}
 # end

  defp assign_chart(%{assigns: %{contact_dataset: contact_dataset,
                                 conversation_dataset: conversation_dataset}} = socket) do
    socket
    |> assign(:contact_chart, make_bar_chart(contact_dataset))
    |> assign(:conversation_chart, make_bar_chart(conversation_dataset))
  end

  defp make_bar_chart(dataset) do
    Contex.BarChart.new(dataset)
  end

  def assign_chart_svg(%{assigns: %{contact_chart: contact_chart,
                                    conversation_chart: conversation_chart}} = socket) do
    socket
    |> assign(:contact_chart_svg, render_bar_chart(contact_chart))
    |> assign(:conversation_chart_svg, render_bar_chart(conversation_chart))
  end

  defp render_bar_chart(chart) do
    Plot.new(500, 400, chart)
    |> Plot.to_svg()
  end

end
