module ML

using GenieFramework
using CSV, DataFrames, Dates, SQLite, StatsBase, Plots
using StateSpaceModels  # For ETS forecasting
@genietools

# Database setup
const DB_PATH = "data/production_data.sqlite"

function create_database()
    db = SQLite.DB(DB_PATH)
    SQLite.execute(db, """
        CREATE TABLE IF NOT EXISTS fact_prod_data (
            fecha_data DATE,
            empresa TEXT,
            areayacimiento TEXT,
            cuenca TEXT,
            provincia TEXT,
            idpozo TEXT,
            prod_pet REAL,
            prod_gas REAL,
            prod_agua REAL,
            PRIMARY KEY (fecha_data, idpozo)
        )
    """)
    SQLite.execute(db, """
        CREATE TABLE IF NOT EXISTS forecasts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            forecast_date DATE,
            grouping_type TEXT,
            grouping_value TEXT,
            period_date DATE,
            prod_pet_forecast REAL,
            prod_gas_forecast REAL,
            prod_agua_forecast REAL
        )
    """)
    return db
end

const db = create_database()

function process_csv(file_path)
    df = CSV.read(file_path, DataFrame)
    selected_columns = [:fecha_data, :empresa, :areayacimiento, :cuenca, :provincia, :idpozo, :prod_pet, :prod_gas, :prod_agua]
    df = df[:, selected_columns]
    df.fecha_data = Date.(df.fecha_data)
    
    # Upsert data into the database
    for row in eachrow(df)
        SQLite.execute(db, """
            INSERT OR REPLACE INTO fact_prod_data
            (fecha_data, empresa, areayacimiento, cuenca, provincia, idpozo, prod_pet, prod_gas, prod_agua)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (row.fecha_data, row.empresa, row.areayacimiento, row.cuenca, row.provincia, row.idpozo, row.prod_pet, row.prod_gas, row.prod_agua))
    end
end

function get_grouping_options(grouping_column)
    query = "SELECT DISTINCT $grouping_column FROM fact_prod_data"
    df = DBInterface.execute(db, query) |> DataFrame
    return df[!, 1]
end

function perform_forecast(grouping_type, grouping_value, start_date, end_date, forecast_periods)
    query = """
        SELECT fecha_data, prod_pet, prod_gas, prod_agua
        FROM fact_prod_data
        WHERE $grouping_type = ? AND fecha_data BETWEEN ? AND ?
        ORDER BY fecha_data
    """
    df = DBInterface.execute(db, query, (grouping_value, start_date, end_date)) |> DataFrame

    forecasts = Dict()
    for variable in [:prod_pet, :prod_gas, :prod_agua]
        ts = df[!, variable]
        model = StateSpaceModels.auto_ets(ts)
        forecast = StateSpaceModels.forecast(model, forecast_periods)
        forecasts[variable] = forecast.mean
    end

    # Save forecasts to database
    forecast_dates = Date(end_date) .+ Dates.Month.(1:forecast_periods)
    for (i, forecast_date) in enumerate(forecast_dates)
        SQLite.execute(db, """
            INSERT INTO forecasts
            (forecast_date, grouping_type, grouping_value, period_date, prod_pet_forecast, prod_gas_forecast, prod_agua_forecast)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (Date(now()), grouping_type, grouping_value, forecast_date, forecasts[:prod_pet][i], forecasts[:prod_gas][i], forecasts[:prod_agua][i]))
    end

    return forecasts
end

@app begin
    @in uploaded_file = ""
    @in grouping_type = "empresa"
    @in grouping_value = ""
    @in start_date = Date(2015, 1, 1)
    @in end_date = Date(2017, 1, 1)
    @in forecast_periods = 12
    @out grouping_options = String[]
    @out forecast_result = Dict()
    @out plot_data = nothing

    @onchange uploaded_file begin
        if !isempty(uploaded_file)
            process_csv(uploaded_file)
        end
    end

    @onchange grouping_type begin
        grouping_options = get_grouping_options(grouping_type)
    end

    @onchange isready begin
        grouping_options = get_grouping_options(grouping_type)
    end

    @onchange grouping_value, start_date, end_date, forecast_periods begin
        if !isempty(grouping_value)
            forecast_result = perform_forecast(grouping_type, grouping_value, start_date, end_date, forecast_periods)
            
            # Prepare plot data
            query = """
                SELECT fecha_data, prod_pet, prod_gas, prod_agua
                FROM fact_prod_data
                WHERE $grouping_type = ? AND fecha_data BETWEEN ? AND ?
                ORDER BY fecha_data
            """
            historical_data = DBInterface.execute(db, query, (grouping_value, start_date, end_date)) |> DataFrame
            
            forecast_dates = Date(end_date) .+ Dates.Month.(1:forecast_periods)
            
            plot_data = plot(historical_data.fecha_data, historical_data.prod_pet, label="Historical Pet", title="Production Forecast")
            plot!(forecast_dates, forecast_result[:prod_pet], label="Forecast Pet")
            plot!(historical_data.fecha_data, historical_data.prod_gas, label="Historical Gas")
            plot!(forecast_dates, forecast_result[:prod_gas], label="Forecast Gas")
            plot!(historical_data.fecha_data, historical_data.prod_agua, label="Historical Agua")
            plot!(forecast_dates, forecast_result[:prod_agua], label="Forecast Agua")
        end
    end
end

@page("/", "ML_ui.jl.html")
#= @page("/", "ui.jl") =#

end


