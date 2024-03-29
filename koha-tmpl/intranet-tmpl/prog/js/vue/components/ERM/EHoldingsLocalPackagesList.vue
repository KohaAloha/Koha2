<template>
    <div>
        <div v-if="!initialized">{{ $__("Loading") }}</div>
        <div v-else-if="package_count" id="packages_list">
            <Toolbar />
            <div
                v-if="package_count > 0"
                id="package_list_result"
                class="page-section"
            >
                <table :id="table_id"></table>
            </div>
            <div v-else-if="initialized" class="dialog message">
                {{ $__("There are no packages defined") }}
            </div>
        </div>
    </div>
</template>

<script>
import Toolbar from "./EHoldingsLocalPackagesToolbar.vue"
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

        const table_id = "package_list"
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
            package_count: [],
            initialized: false,
            filters: {
                package_name: this.$route.query.package_name || "",
                content_type: this.$route.query.content_type || "",
            },
        }
    },
    beforeRouteEnter(to, from, next) {
        next(vm => {
            vm.getPackageCount().then(() => vm.build_datatable())
        })
    },
    methods: {
        async getPackageCount() {
            const client = APIClient.erm
            await client.localPackages.count().then(
                count => {
                    this.package_count = count
                    this.initialized = true
                },
                error => {}
            )
        },
        show_package: function (package_id) {
            this.$router.push(
                "/cgi-bin/koha/erm/eholdings/local/packages/" + package_id
            )
        },
        edit_package: function (package_id) {
            this.$router.push(
                "/cgi-bin/koha/erm/eholdings/local/packages/edit/" + package_id
            )
        },
        delete_package: function (package_id, package_name) {
            this.setConfirmationDialog(
                {
                    title: this.$__(
                        "Are you sure you want to remove this package?"
                    ),
                    message: package_name,
                    accept_label: this.$__("Yes, delete"),
                    cancel_label: this.$__("No, do not delete"),
                },
                () => {
                    const client = APIClient.erm
                    client.localPackages.delete(package_id).then(
                        success => {
                            this.setMessage(
                                this.$__("Local package %s deleted").format(
                                    package_name
                                ),
                                true
                            )
                            $("#" + this.table_id)
                                .DataTable()
                                .ajax.url(
                                    "/api/v1/erm/eholdings/local/packages"
                                )
                                .draw()
                        },
                        error => {}
                    )
                }
            )
        },
        build_datatable: function () {
            let show_package = this.show_package
            let edit_package = this.edit_package
            let delete_package = this.delete_package
            let get_lib_from_av = this.get_lib_from_av
            let map_av_dt_filter = this.map_av_dt_filter
            let filters = this.filters
            let table_id = this.table_id

            window["vendors"] = this.vendors.map(e => {
                e["_id"] = e["id"]
                e["_str"] = e["name"]
                return e
            })
            let avs = ["av_package_types", "av_package_content_types"]
            avs.forEach(function (av_cat) {
                window[av_cat] = map_av_dt_filter(av_cat)
            })

            $("#" + table_id).kohaTable(
                {
                    ajax: {
                        url: "/api/v1/erm/eholdings/local/packages",
                    },
                    embed: ["resources+count", "vendor.name"],
                    order: [[0, "asc"]],
                    autoWidth: false,
                    searchCols: [
                        { search: filters.package_name },
                        null,
                        null,
                        { search: filters.content_type },
                        null,
                        null,
                    ],
                    columns: [
                        {
                            title: __("Name"),
                            data: "me.package_id:me.name",
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
                                return row.vendor
                                    ? escape_str(row.vendor.name)
                                    : ""
                            },
                        },
                        {
                            title: __("Type"),
                            data: "package_type",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return escape_str(
                                    get_lib_from_av(
                                        "av_package_types",
                                        row.package_type
                                    )
                                )
                            },
                        },
                        {
                            title: __("Content type"),
                            data: "content_type",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return escape_str(
                                    get_lib_from_av(
                                        "av_package_content_types",
                                        row.content_type
                                    )
                                )
                            },
                        },
                        {
                            title: __("Created on"),
                            data: "created_on",
                            searchable: false,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return $date(row.created_on)
                            },
                        },
                        {
                            title: __("Notes"),
                            data: "notes",
                            searchable: true,
                            orderable: true,
                            render: function (data, type, row, meta) {
                                return row.notes
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
                                let package_id = api.row(tr).data().package_id
                                let package_name = api.row(tr).data().name
                                let editButton = createVNode(
                                    "a",
                                    {
                                        class: "btn btn-default btn-xs",
                                        role: "button",
                                        onClick: () => {
                                            edit_package(package_id)
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
                                            delete_package(
                                                package_id,
                                                package_name
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
                                            "/cgi-bin/koha/erm/eholdings/local/packages/" +
                                            row.package_id,
                                        onClick: e => {
                                            e.preventDefault()
                                            show_package(row.package_id)
                                        },
                                    },
                                    `${row.name} (#${row.package_id})`
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
                            .eq(2)
                            .attr("data-filter", "av_package_types")
                        $("#" + table_id)
                            .find("thead th")
                            .eq(3)
                            .attr("data-filter", "av_package_content_types")
                    },
                },
                eholdings_packages_table_settings,
                1
            )
        },
    },
    components: { Toolbar },
    name: "EHoldingsLocalPackagesList",
}
</script>
