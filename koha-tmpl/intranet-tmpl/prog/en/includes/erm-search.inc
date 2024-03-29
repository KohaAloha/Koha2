[% USE Koha %]
<!-- erm-search.inc -->
<div id="header_search" role="tablist">
    <div class="tab-content">
        <div id="agreement_search" role="tabpanel" class="tab-pane active">
            <form action="/cgi-bin/koha/erm/agreements" method="get">
                <div class="form-title">
                    <label class="control-label">Agreement search</label>
                </div>
                <div class="form-content">
                    <input type="text" name="q" id="agreement_filter" class="head-searchbox form-control" placeholder="Enter search keywords" size="40" />
                </div>
                <button type="submit"><i class="fa fa-arrow-right"></i></button>
            </form>
        </div>

        <div id="package_search" role="tabpanel" class="tab-pane">
            <form action="/cgi-bin/koha/erm/eholdings/local/packages" method="get">
                <div class="form-title">
                    <label class="control-label">Package search</label>
                </div>
                <div class="form-content">
                    <input type="text" name="package_name" id="package_name_filter" class="head-searchbox form-control" placeholder="Enter search keywords" size="40" />
                </div>
                <button type="submit"><i class="fa fa-arrow-right"></i></button>
            </form>
        </div>

        <div id="title_search" role="tabpanel" class="tab-pane">
            <form action="/cgi-bin/koha/erm/eholdings/local/titles" method="get">
                <div class="form-title">
                    <label class="control-label">Title search</label>
                </div>
                <div class="form-content">
                    <input type="text" name="publication_title" id="title_filter" class="head-searchbox form-control" placeholder="Enter search keywords" size="40" />
                </div>
                <button type="submit"><i class="fa fa-arrow-right"></i></button>
            </form>
        </div>
    </div><!-- /.tab-content -->

    <ul class="nav nav-tabs" role="tablist">
        <li role="presentation" class="active">
            <a title="Search agreements" href="#agreement_search" aria-controls="agreement_search" role="tab" aria-expanded="true" data-toggle="tab" class="keep_text"><i class="fa fa-check-circle-o"></i> <span class="tab-title">Search agreements</span></a>
        </li>
        <li role="presentation">
            <a title="Search packages" href="#package_search" aria-controls="package_search" role="tab" data-toggle="tab" class="keep_text"><i class="fa fa-archive"></i> <span class="tab-title">Search packages</span></a>
        </li>
        <li role="presentation">
            <a title="Search titles" href="#title_search" aria-controls="title_search" role="tab" data-toggle="tab" class="keep_text"><i class="fa fa-sort-alpha-asc"></i> <span class="tab-title">Search titles</span></a>
        </li>
    </ul>
</div><!-- /#header_search -->
<!-- /erm-search.inc -->
