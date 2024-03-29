<template>
    <div v-if="!initialized">{{ $__("Loading") }}</div>
    <div v-else-if="licenses" id="licenses_list">
        <Toolbar />
        <div v-if="licenses.length" class="page-section">
            <table :id="table_id"></table>
        </div>
        <div v-else-if="initialized" class="dialog message">
            {{ $__("There are no licenses defined") }}
        </div>
    </div>
</template>

<script>
import Toolbar from "./LicensesToolbar.vue"
import { inject, createVNode, render } from "vue"
import { storeToRefs } from "pinia"
import { APIClient } from "../../fetch/api-client.js"
import { useDataTable } from "../../composables/datatables"

export default {
    setup() {
        const vendorStore = inject("vendorStore")
        const { vendors } = storeToRefs(vendorStore)

        const AVStore = inject("AVStore")
        const { get_lib_from_av, map_av_dt_filter } = AVStore

        const { setConfirmationDialog, setMessage } = inject("mainStore")

        const table_id = "license_list"
        useDataTable(table_id)

        return {
            vendors,
            get_lib_from_av,
            map_av_dt_filter,
            table_id,
            setConfirmationDialog,
            setMessage,
        }
    },
    data: function () {
        return {
            licenses: [],
            initialized: false,
        }
    },
    beforeRouteEnter(to, from, next) {
        next(vm => {
            vm.getLicenses().then(() => vm.build_datatable())
        })
    },
    methods: {
        async getLicenses() {
            const client = APIClient.erm
            await client.licenses.getAll().then(
                licenses => {
                    this.licenses = licenses
                    this.initialized = true
                },
                error => {}
            )
        },
        show_license: function (license_id) {
            this.$router.push("/cgi-bin/koha/erm/licenses/" + license_id)
        },
        edit_license: function (license_id) {
            this.$router.push("/cgi-bin/koha/erm/licenses/edit/" + license_id)
        },
        delete_license: function (license_id, license_name) {
            this.setConfirmationDialog(
                {
                    title: this.$__(
                        "Are you sure you want to remove this license?"
                    ),
                    message: license_name,
                    accept_label: this.$__("Yes, delete"),
                    cancel_label: this.$__("No, do not delete"),
                },
                () => {
                    const client = APIClient.erm
                    client.licenses.delete(license_id).then(
                        success => {
                            this.setMessage(
                                this.$__("License %s deleted").format(
                                    license_name
                                ),
                                true
                            )
                            $("#" + this.table_id)
                                .DataTable()
                                .ajax.url("/api/v1/erm/licenses")
                                .draw()
                        },
                        error => {}
                    )
                }
            )
        },
        build_datatable: function () {
            let show_license = this.show_license
            let edit_license = this.edit_license
            let delete_license = this.delete_license
            let get_lib_from_av = this.get_lib_from_av
            let map_av_dt_filter = this.map_av_dt_filter
            let default_search = this.$route.query.q
            let table_id = this.table_id

            window["vendors"] = this.vendors.map(e => {
                e["_id"] = e["id"]
                e["_str"] = e["name"]
                return e
            })
            let vendors_map = this.vendors.reduce((map, e) => {
                map[e.id] = e
                return map
            }, {})
            let avs = ["av_license_types", "av_license_statuses"]
            avs.forEach(function (av_cat) {
                window[av_cat] = map_av_dt_filter(av_cat)
            })

            $("#" + table_id).kohaTable(
                {
                    ajax: {
                        url: "/api/v1/erm/licenses",
                    },
                    order: [[0, "asc"]],
                    search: { search: default_search },
                    columnDefs: [
                        {
                            targets: [0, 1],
                            render: function (data, type, row, meta) {
                                if (type == "display") {
                                    return escape_str(data)
                                }
                                return data
                            },
                        },
                    ],
                    columns: [
                        {
                            title: __("Name"),
                            data: "me.license_id:me.name",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                // Rendering done in drawCallback
                                return ""
                            },
                        },
                        {
                            title: __("Vendor"),
                            data: "vendor_id",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return row.vendor_id != undefined
                                    ? escape_str(
                                          vendors_map[row.vendor_id].name
                                      )
                                    : ""
                            },
                        },

                        {
                            title: __("Description"),
                            data: "description",
                            searchable: true,
                            orderable: true,
                        },
                        {
                            title: __("Type"),
                            data: "type",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return escape_str(
                                    get_lib_from_av(
                                        "av_license_types",
                                        row.type
                                    )
                                )
                            },
                        },
                        {
                            title: __("Status"),
                            data: "status",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return escape_str(
                                    get_lib_from_av(
                                        "av_license_statuses",
                                        row.status
                                    )
                                )
                            },
                        },
                        {
                            title: __("Started on"),
                            data: "started_on",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return $date(row.started_on)
                            },
                        },
                        {
                            title: __("Ended on"),
                            data: "ended_on",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return $date(row.ended_on)
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
                                let license_id = api.row(tr).data().license_id
                                let license_name = api.row(tr).data().name
                                let editButton = createVNode(
                                    "a",
                                    {
                                        class: "btn btn-default btn-xs",
                                        role: "button",
                                        onClick: () => {
                                            edit_license(license_id)
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
                                            delete_license(
                                                license_id,
                                                license_name
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
                                        onClick: () => {
                                            show_license(row.license_id)
                                        },
                                    },
                                    `${row.name} (#${row.license_id})`
                                )
                                render(n, e)
                            }
                        )
                    },
                    preDrawCallback: function (settings) {
                        $("#" + table_id)
                            .find("thead th")
                            .eq(1)
                            .attr("data-filter", "vendors")
                        $("#" + table_id)
                            .find("thead th")
                            .eq(3)
                            .attr("data-filter", "av_license_types")
                        $("#" + table_id)
                            .find("thead th")
                            .eq(4)
                            .attr("data-filter", "av_license_statuses")
                    },
                },
                license_table_settings,
                1
            )
        },
    },
    props: {
        av_license_types: Array,
        av_license_statuses: Array,
    },
    components: { Toolbar },
    name: "LicensesList",
}
</script>
