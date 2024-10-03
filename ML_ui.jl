
header(class="st-header q-pa-sm",
    h1(draggable="true", class="st-header__title text-h3",
        "Time Series Analysis"
    )
)
cell(class="row", [
    cell(class="st-col col-6 col-sm st-module", [
        h3("Parameters"),
        p("Upload file to add to Database"),
        fileinput("Upload CSV", :uploaded_file),
        p("Select the aggregation level"),
        select(:grouping_type, options=["empresa", "areayacimiento", "cuenca", "provincia", "idpozo"], label="Grouping Type"),
        p("Group to train"),
        select(:grouping_value, :grouping_options, label="Grouping Value"),
        p("Start Date"),
        date(:start_date, label="Start Date"),
        p("End Date"),
        date(:end_date, label="End Date"),
        p("Forecasting Range"),
        slider(1:1:36, :forecast_periods, label="Forecast Periods (Months)"),
        br(),
        cell(class="row",
            cell(class="st-col col-6 col-sm", [
                                               btn("TRAIN", class="q-mr-sm", color=button_color, @click("train = !train"), loading=:training, textcolor="black", disable=disable_train,[button_tooltip]),
                                               btn("SAVE", color=button_color, @click("save = !save"),disable=disable_train,[button_tooltip], textcolor="black",)
            ])
        )
    ]),
    cell(class="st-col col-6 col-sm st-module",
        plot(:plot_data)
    )
])
