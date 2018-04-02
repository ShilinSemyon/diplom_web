class RealDataYController < ApplicationController
  respond_to :html, :js, :json

  before_action :init_user
  # before_action :init_real_data_y, only: %i[new]
  before_action :init_data_y, only: %i[draw]
  before_action :init_global_option_chart, only: %i[draw show]

  def show
    @mnk = "MNK::#{allowed_chart_params[:chart].camelize}".safe_constantize

    data_x = @user.data_xes.where(document_id: session[:document_id]).order(:percent).distinct.pluck(:percent)
    real_data_x = @user.data_xes.where(document_id: session[:real_document_id]).order(:percent).distinct.pluck(:percent)
    data_y = @user.grouped_by_gene(session[:document_id])[params[:gene]]
    real_data_y = @user.grouped_by_gene_real_y_without_id(session[:real_document_id])[params[:gene]]

    @coordinates = @mnk.new(data_x: real_data_x, data_y: real_data_y,
                            custom_coords: Equations.calculate_points(data_x, data_y))
  end

  def new
    @information = Information.new({})
  end

  def create
    @information = Information.new(real_y_params)
    ParsingExcelJob.perform_now(@information.path, session[:uid], @information.real_y)
    # sleep 2

    session[:real_document_id] = @user.documents.last.id

    @data_x = @user.data_xes.order(:percent).distinct.pluck(:percent)
    @data_y = @user.grouped_by_gene_real_y( session[:real_document_id])

    render :create, layout: false
  end

  def draw
    # approx_coordinates_cub_p = MNK::CubicParabola.new(data_x: @data_x, data_y: @data_y)#.process
    # y = parabola.search_points(@coefficients_cub_p, 25)

    @coordinates_cub_p = MNK::CubicParabola.new(data_x: @data_x, data_y: @data_y)
    @coordinates_hyp = MNK::Hyperbola.new(data_x: @data_x, data_y: @data_y)
    @coordinates_cub_p_e = MNK::CubicParabolaWithExtremes.new(data_x: @data_x, data_y: @data_y)

    approx_data_hash = { cub_p: @coordinates_cub_p.approx_y.values, cub_p_e: @coordinates_hyp.approx_y.values, hyp: @coordinates_cub_p_e.approx_y.values }
    # pp @mist = Supports::Mistake.calculate(@data_y, approx_data_hash)
    @mist = Supports::Mistake.chart(@data_y, approx_data_hash)
  end

  def search
    @data_x = @user.data_xes.order(:percent).distinct.pluck(:percent)
    @data_y = @user.grouped_by_gene(session[:document_id])#[params[:gene]]
    @mnk = "MNK::#{allowed_chart_params[:chart].camelize}".safe_constantize

    if params[:gene]
      coords = Equations.calculate_points(@data_x, @data_y[params[:gene]])
      object = @mnk.new(data_x: @data_x, data_y: @data_y[params[:gene]])
      approx_coordinates = object.process
      @coordinates = [{ name: @mnk.to_s.demodulize, data: coords, type: 'line' }, { name: "#{@mnk.to_s.demodulize} approx coordinates", data: approx_coordinates.approx_y, type: 'spline' }]
    else
      approx_coordinates = {}
      coords = {}
      @coordinates = []
      @data_y.each do |gen, value|
        coords[gen] = Equations.calculate_points(@data_x, value)
        object = @mnk.new(data_x: @data_x, data_y: value)
        approx_coordinates[gen] = object.process
      end
    end

    real_x = {}
    needed_values = params[:gene] ? @user.grouped_by_gene_real_y_without_id_long(session[:real_document_id])[params[:gene]] : @user.grouped_by_gene_real_y_without_id_long(session[:real_document_id]).values
    gene_v = []
    needed_values.each_with_index do |data, index|
      data.shift unless params[:gene]
      real_x[index] = {}
      if params[:gene]
        key = object.search_points(object.coefficients, data) || 0
        real_x[index][key] ||= []
        real_x[index][key] << data

        real_x[index].reject! { |k, _| k == 0 }
        gene_v << real_x[index].transform_values { |v| v&.at(0).to_f }.sort_by { |_, v| v }.to_h
      else
        data.each do |d|
          key = object.search_points(object.coefficients, d) || 0
          real_x[index][key] ||= []
          real_x[index][key] << d
        end
        real_x[index].reject! { |k, _| k == 0}
        temp = real_x[index].transform_values { |v| v&.at(0).to_f }.sort_by { |_, v| v }.to_h
        @coordinates.push({ name: (index + 1).to_s, data: temp, type: 'spline' })
      end
    end
    @coordinates.push({ name: 1, data: gene_v.map { |h| h.to_a.flatten }, type: 'spline'}) if params[:gene]

    render :search, layout: false
  end

  private

  def allowed_chart_params
    allowed_chart = %w(cubic_parabola cubic_parabola_with_extremes hyperbola)
    params.permit(:uid, :gene, :chart, :real_id, :all)
    params.delete(:chart) unless params[:chart].in? allowed_chart
    params
  end

  def init_real_data_y
    @user = User.find_by_uid(session[:uid])
    @data_x = @user.data_xes.where(document_id: session[:real_document_id]).order(:percent).distinct.pluck(:percent)
    data_y = @user.grouped_by_gene_real_y_without_id(session[:real_document_id])
    @data_y = action_name == 'all' ? data_y.values : data_y[params[:gene]]
  end

  def init_data_y
    # @user = User.includes(:data_xes, :data_ies, :genes).find_by_uid(session[:uid])
    @data_x = @user.data_xes.where(document_id: session[:document_id]).order(:percent).distinct.pluck(:percent)
    data_y = @user.grouped_by_gene(session[:document_id])
    @data_y = action_name == 'all' ? data_y.values : data_y[params[:gene]]
  end

  def real_y_params
    params.require(:information).permit(:real_y, :excel, :uid, :remotipart_submitted, :authenticity_token, :'X-Requested-With', :'X-Http-Accept')
  end

  def init_global_option_chart
    @chart_globals = LazyHighCharts::HighChartGlobals.new do |f|
      f.global(useUTC: false)
      f.chart(
        width: 700,
        zoomType: 'xy',
        marginBottom: '100',
        height: 500
      )
      f.lang(
        loading: 'Загрузка...',
        months: ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'],
        weekdays: ['Воскресенье', 'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'],
        shortMonths: ['Янв', 'Фев', 'Март', 'Апр', 'Май', 'Июнь', 'Июль', 'Авг', 'Сент', 'Окт', 'Нояб', 'Дек'],
        exportButtonTitle: "Экспорт",
        printButtonTitle: "Печать",
        rangeSelectorFrom: "С",
        rangeSelectorTo: "По",
        rangeSelectorZoom: "Период",
        downloadPNG: 'Скачать PNG',
        downloadJPEG: 'Скачать JPEG',
        downloadPDF: 'Скачать PDF',
        downloadSVG: 'Скачать SVG',
        printChart: 'Напечатать график')
    end
  end

  def init_user
    @user = User.includes(:data_xes, :data_ies, :genes).find_by_uid(session[:uid])
  end
end
