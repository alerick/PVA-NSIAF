class EntitiesController < ApplicationController
  before_action :set_entity, only: [:edit, :update, :destroy, :show]

  # GET /entities
  # GET /entities.json
  def index
    respond_to do |format|
      format.html { render '/shared/index' }
      format.json { render json: EntitiesDatatable.new(view_context) }
    end
  end

  def show
  end

  # GET /entities/new
  def new
    @entity = Entity.new
    respond_to do |format|
      format.html { render 'form' }
    end
  end

  # GET /entities/1/edit
  def edit
    respond_to do |format|
      format.html { render 'form' }
    end
  end

  # POST /entities
  # POST /entities.json
  def create
    @entity = Entity.new(entity_params)

    respond_to do |format|
      if @entity.save
        format.html { redirect_to entities_url, notice: t('general.created', model: Entity.model_name.human) }
        format.json { render action: 'show', status: :created, location: @entity }
      else
        format.html { render action: 'form' }
        format.json { render json: @entity.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /entities/1
  # PATCH/PUT /entities/1.json
  def update
    respond_to do |format|
      if @entity.update(entity_params)
        format.html { redirect_to entities_url, notice: t('general.updated', model: Entity.model_name.human) }
        format.json { head :no_content }
      else
        format.html { render action: 'form' }
        format.json { render json: @entity.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /entities/1
  # DELETE /entities/1.json
  def destroy
    @entity.destroy
    respond_to do |format|
      format.html { redirect_to entities_url, notice: t('general.destroy', name: @entity.name) }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_entity
      @entity = Entity.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def entity_params
      params.require(:entity).permit(:code, :name, :acronym)
    end
end
