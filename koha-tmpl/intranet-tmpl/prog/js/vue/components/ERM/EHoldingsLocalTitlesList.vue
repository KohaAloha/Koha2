<template>
    <div>
        <div v-if="!initialized">{{ $__("Loading") }}</div>
        <div v-else-if="title_count" id="titles_list">
            <Toolbar />
            <div
                v-if="title_count > 0"
                id="title_list_result"
                class="page-section"
            >
                <table :id="table_id"></table>
            </div>
            <div v-else-if="initialized" class="dialog message">
                {{ $__("There are no titles defined") }}
            </div>
        </div>
    </div>
</template>

<script>
import Toolbar from "./EHoldingsLocalTitlesToolbar.vue"
import { inject, createVNode, render } from "vue"
import { storeToRefs } from "pinia"
import { APIClient } from "../../fetch/api-client.js"
import { useDataTable } from "../../composables/datatables"

export default {
    setup() {
        const AVStore = inject("AVStore")
        const { av_title_publication_types } = storeToRefs(AVStore)
        const { get_lib_from_av, map_av_dt_filter } = AVStore

        const { setConfirmationDialog, setMessage } = inject("mainStore")

        const table_id = "title_list"
        useDataTable(table_id)

        return {
            av_title_publication_types,
            get_lib_from_av,
            map_av_dt_filter,
            table_id,
            setConfirmationDialog,
            setMessage,
        }
    },
    data: function () {
        return {
            title_count: undefined,
            initialized: false,
            filters: {
                publication_title: this.$route.query.publication_title || "",
                publication_type: this.$route.query.publication_type || "",
            },
            cannot_search: false,
        }
    },
    beforeRouteEnter(to, from, next) {
        next(vm => {
            vm.getTitleCount().then(() => vm.build_datatable())
        })
    },
    methods: {
        async getTitleCount() {
            const client = APIClient.erm
            await client.localTitles.count().then(
                count => {
                    this.title_count = count
                    this.initialized = true
                },
                error => {}
            )
        },
        show_title: function (title_id) {
            this.$router.push(
                "/cgi-bin/koha/erm/eholdings/local/titles/" + title_id
            )
        },
        edit_title: function (title_id) {
            this.$router.push(
                "/cgi-bin/koha/erm/eholdings/local/titles/edit/" + title_id
            )
        },
        delete_title: function (title_id, title_publication_title) {
            this.setConfirmationDialog(
                {
                    title: this.$__(
                        "Are you sure you want to remove this title?"
                    ),
                    message: title_publication_title,
                    accept_label: this.$__("Yes, delete"),
                    cancel_label: this.$__("No, do not delete"),
                },
                () => {
                    const client = APIClient.erm
                    client.localTitles.delete(title_id).then(
                        success => {
                            this.setMessage(
                                this.$__("Local title %s deleted").format(
                                    title_publication_title
                                ),
                                true
                            )
                            $("#" + this.table_id)
                                .DataTable()
                                .ajax.url("/api/v1/erm/eholdings/local/titles")
                                .draw()
                        },
                        error => {}
                    )
                }
            )
        },
        build_datatable: function () {
            let show_title = this.show_title
            let edit_title = this.edit_title
            let delete_title = this.delete_title
            let get_lib_from_av = this.get_lib_from_av
            let map_av_dt_filter = this.map_av_dt_filter
            let filters = this.filters
            let table_id = this.table_id

            window["av_title_publication_types"] = map_av_dt_filter(
                "av_title_publication_types"
            )

            $("#" + table_id).kohaTable(
                {
                    ajax: {
                        url: "/api/v1/erm/eholdings/local/titles",
                    },
                    embed: ["resources.package"],
                    order: [[0, "asc"]],
                    autoWidth: false,
                    searchCols: [
                        { search: filters.publication_title },
                        null,
                        { search: filters.publication_type },
                        null,
                    ],
                    columns: [
                        {
                            title: __("Title"),
                            data: "me.publication_title",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                // Rendering done in drawCallback
                                return ""
                            },
                        },
                        {
                            title: __("Contributors"),
                            data: "first_author:first_editor",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return (
                                    escape_str(row.first_author) +
                                    (row.first_author && row.first_editor
                                        ? "<br/>"
                                        : "") +
                                    escape_str(row.first_editor)
                                )
                            },
                        },
                        {
                            title: __("Publication type"),
                            data: "publication_type",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return escape_str(
                                    get_lib_from_av(
                                        "av_title_publication_types",
                                        row.publication_type
                                    )
                                )
                            },
                        },
                        {
                            title: __("Identifier"),
                            data: "print_identifier:online_identifier",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                let print_identifier = row.print_identifier
                                let online_identifier = row.online_identifier
                                return (
                                    (print_identifier
                                        ? escape_str(
                                              _("ISBN (Print): %s").format(
                                                  print_identifier
                                              )
                                          )
                                        : "") +
                                    (online_identifier
                                        ? escape_str(
                                              _("ISBN (Online): %s").format(
                                                  online_identifier
                                              )
                                          )
                                        : "")
                                )
                            },
                        },
                        {
                            title: __("Actions"),
                            data: function (row, type, val, meta) {
                                return '<div class="actions"></div>'
                            },
                            className: "actions noExport",
                            searchable: false,
                            orderable: false,
                        },
                    ],
                    drawCallback: function (settings) {
                        var api = new $.fn.dataTable.Api(settings)

                        $.each(
                            $(this).find("td .actions"),
                            function (index, e) {
                                let tr = $(this).parent().parent()
                                let title_id = api.row(tr).data().title_id
                                let title_publication_title = api
                                    .row(tr)
                                    .data().publication_title
                                let editButton = createVNode(
                                    "a",
                                    {
                                        class: "btn btn-default btn-xs",
                                        role: "button",
                                        onClick: () => {
                                            edit_title(title_id)
                                        },
                                    },
                                    [
                                        createVNode("i", {
                                            class: "fa fa-pencil",
                                            "aria-hidden": "true",
                                        }),
                                        __("Edit"),
                                    ]
                                )

                                let deleteButton = createVNode(
                                    "a",
                                    {
                                        class: "btn btn-default btn-xs",
                                        role: "button",
                                        onClick: () => {
                                            delete_title(
                                                title_id,
                                                title_publication_title
                                            )
                                        },
                                    },
                                    [
                                        createVNode("i", {
                                            class: "fa fa-trash",
                                            "aria-hidden": "true",
                                        }),
                                        __("Delete"),
                                    ]
                                )

                                let n = createVNode("span", {}, [
                                    editButton,
                                    " ",
                                    deleteButton,
                                ])
                                render(n, e)
                            }
                        )

                        $.each(
                            $(this).find("tbody tr td:first-child"),
                            function (index, e) {
                                let tr = $(this).parent()
                                let row = api.row(tr).data()
                                if (!row) return // Happen if the table is empty
                                let n = createVNode(
                                    "a",
                                    {
                                        role: "button",
                                        href:
                                            "/cgi-bin/koha/erm/eholdings/local/titles/" +
                                            row.title_id,
                                        onClick: e => {
                                            e.preventDefault()
                                            show_title(row.title_id)
                                        },
                                    },
                                    `${row.publication_title} (#${row.title_id})`
                                )
                                render(n, e)
                            }
                        )
                    },
                    preDrawCallback: function (settings) {
                        $("#" + table_id)
                            .find("thead th")
                            .eq(2)
                            .attr("data-filter", "av_title_publication_types")
                    },
                },
                eholdings_titles_table_settings,
                1
            )
        },
    },
    components: { Toolbar },
    name: "EHoldingsLocalTitlesList",
}
</script>
