class InformationController < ApplicationController
  respond_to :html, :js, :json
  layout false, only: :create
  before_action :init_data, only: %i[draw all]

  def index
    @user = User.all.first
    session[:document_id] = @user&.documents&.last&.id
  end

  def new
    @information = Information.new
  end

  def create
    @information = Information.new(information_params)
    params = { path: @information.path, uid: session[:uid], name: @information.name }
    Information.new(params).create
    # ParsingExcelJob.perform_now(@information.path, session[:uid])

    @user = User.all.first
    session[:document_id] = @user&.documents&.last&.id
    redirect_to action: :all
  end

  def all
    @header = @user.genes.order(:id).pluck(:name).uniq
    @body = @data_y.unshift(@data_x).uniq.transpose
  end

  def draw
    coords = Equations.calculate_points(@data_x, @data_y)

    approx_coordinates_cub_p = MNK::CubicParabola.new(data_x: @data_x, data_y: @data_y).process
    @coordinates_cub_p = [{ name: 'cub_p', data: coords }, { name: 'cub_p approx coordinates', data: approx_coordinates_cub_p.approx_y }]#, { name: 'point', data: { y => 25 } }]

    approx_coordinates_hyp = MNK::Hyperbola.new(data_x: @data_x, data_y: @data_y).process
    @coordinates_hyp = [{name: 'hyp', data: coords}, {name: 'hyp approx coordinates', data: approx_coordinates_hyp.approx_y}]

    approx_coordinates_cub_p_e = MNK::CubicParabolaWithExtremes.new(data_x: @data_x, data_y: @data_y).process
    @coordinates_cub_p_e = [{name: 'cub_p_e', data: coords}, {name: 'cub_p_e approx coordinates', data: approx_coordinates_cub_p_e.approx_y}]

    approx_data_hash = { cub_p: approx_coordinates_cub_p.approx_y.values, cub_p_e: approx_coordinates_cub_p_e.approx_y.values, hyp: approx_coordinates_hyp.approx_y.values }
    @mist = Supports::Mistake.calculate(@data_y, approx_data_hash)
  end

  private

  def information_params
    params.require(:information).permit(:excel, :gene, :uid)
  end

  def init_data
    @user = User.all.first
    @data_x = @user.data_xes.where(document_id: session[:document_id]).order(:percent).distinct.pluck(:percent)
    data_y = @user.grouped_by_gene(session[:document_id])
    @data_y = action_name == 'all' ? data_y.values : data_y[params[:gene]]
  end
end
