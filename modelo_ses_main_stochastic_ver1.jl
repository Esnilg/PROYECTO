using JuMP, Dsp

include("parametros_inciertos.jl")

prob = ones(NS) / NS; # probabilities

# JuMP model

modelo = Model(NS)

# var I stage

@variable(modelo,TotalCost >= 0);
@variable(modelo,C_inv[i=nTECHNOLOGIES] >=0);
@variable(modelo,C_maint[i=nTECHNOLOGIES] >=0);
@variable(modelo,GWP_constr[i=nTECHNOLOGIES] >= 0);
@variable(modelo,F_Mult[i=nTECHNOLOGIES], lowerbound=f_min[TECHNOLOGIESC[i]], upperbound=f_max[TECHNOLOGIESC[i]]);
@variable(modelo,Number_Of_Units[i=nTECHNOLOGIES] >=0); # ENTERA
@variable(modelo,share_mobility_public_min <= Share_Mobility_Public <= share_mobility_public_max);
@variable(modelo,share_freight_train_min <= Share_Freight_Train <= share_freight_train_max);
@variable(modelo,share_heat_dhn_min <= Share_Heat_Dhn <= share_heat_dhn_max);
@variable(modelo, 0 <= Y_Solar_Backup[i=nTECHNOLOGIES] <= 1); # BINARIA

### OBJECTIVE FUNCTION ###

@objective(modelo, Min, TotalCost);

@constraint(modelo, totalcost_cal, TotalCost == sum(tau[TECHNOLOGIESC[i]]*C_inv[i] + C_maint[i] for i in nTECHNOLOGIES));

# const I stage

# 1.3

@constraint(modelo, investment_cost_calc[i=nTECHNOLOGIES], C_inv[i] == c_inv[TECHNOLOGIESC[i]]*F_Mult[i]);

# 1.4

@constraint(modelo, main_cost_calc[i=nTECHNOLOGIES], C_maint[i] == c_maint[TECHNOLOGIESC[i]] * F_Mult[i]);

# 1.5

@constraint(modelo, gwp_constr_calc[i=nTECHNOLOGIES], GWP_constr[i] == gwp_constr[TECHNOLOGIESC[i]]*F_Mult[i]);

# 1.7 

@constraint(modelo, number_of_units[i=nTECHNOLOGIES; ~in(TECHNOLOGIESC[i],INFRASTRUCTURE)], Number_Of_Units[i] == F_Mult[i]/ref_size[TECHNOLOGIESC[i]]);

# 1.24

@constraint(modelo, storage_level_hydro_dams, F_Mult[TECHNOLOGIESD["PUMPED_HYDRO"]] <= f_max["PUMPED_HYDRO"] * (F_Mult[TECHNOLOGIESD["NEW_HYDRO_DAM"]] - f_min["NEW_HYDRO_DAM"])/(f_max["NEW_HYDRO_DAM"] - f_min["NEW_HYDRO_DAM"]));

# 1.26

@constraint(modelo, extra_dhn, F_Mult[TECHNOLOGIESD["DHN"]] == sum(F_Mult[TECHNOLOGIESD[j]] for j in TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DHN"]));

# 1.28

@constraint(modelo, extra_grid, F_Mult[TECHNOLOGIESD["GRID"]] == 1 + (9400 /c_inv["GRID"]) * (F_Mult[TECHNOLOGIESD["WIND"]] + F_Mult[TECHNOLOGIESD["PV"]])/(f_max["WIND"] + f_max["PV"]));

# 1.29 linealizacion

@constraint(modelo, extra_power2gas_1, F_Mult[TECHNOLOGIESD["POWER2GAS_3"]] >= F_Mult[TECHNOLOGIESD["POWER2GAS_1"]]);

@constraint(modelo, extra_power2gas_2, F_Mult[TECHNOLOGIESD["POWER2GAS_3"]] >= F_Mult[TECHNOLOGIESD["POWER2GAS_2"]]);

# 1.30 no esta en la tesis
                                                                                                                 
@constraint(modelo, extra_efficiency, F_Mult[TECHNOLOGIESD["EFFICIENCY"]] == 1/(1 + i_rate));

# 1.19

@constraint(modelo, op_strategy_decen_2, sum(Y_Solar_Backup[i] for i in nTECHNOLOGIES) <= 1);

# requisito

@constraint(modelo, F_Mult[TECHNOLOGIESD["NUCLEAR"]] == 0.0);

# II STAGE

for s in blockids()
    
    blk = Model(modelo, s, prob[s])

    @variable(blk,TotalCost_stoch >= 0);
    @variable(blk,End_Uses[LAYERS,PERIODS] >=0);
    @variable(blk,F_Mult_t[union(RESOURCES,TECHNOLOGIES),PERIODS] >=0);
    @variable(blk,C_op[RESOURCES] >=0);
    @variable(blk,Storage_In[STORAGE_TECH,LAYERS,PERIODS] >=0);
    @variable(blk,Storage_Out[STORAGE_TECH,LAYERS,PERIODS] >=0);
    @variable(blk,Losses[END_USES_TYPES,PERIODS] >= 0);
    @variable(blk,GWP_op[RESOURCES] >= 0);
    @variable(blk,TotalGWP >= 0);

    # var auxiliar
    @variable(blk,X_Solar_Backup_Aux[setdiff(TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DECEN"],["DEC_SOLAR"]),PERIODS] >= 0);

    # Linearization of Eq. 1.14
    @variable(blk,0 <= Y_Sto_In[STORAGE_TECH,PERIODS] <= 1); # BINARIAS
    @variable(blk,0 <= Y_Sto_Out[STORAGE_TECH,PERIODS]<= 1); # BINARIAS

    # [Eq. 1.27] Calculation of max heat demand in DHN
    @variable(blk,Max_Heat_Demand_DHN >= 0);


    ### OBJECTIVE FUNCTION ###

    @objective(blk, Min, TotalCost_stoch);

    @constraint(blk, totalcost_cal_stoch, TotalCost_stoch == sum(C_op[j] for j in RESOURCES));


    # 1.10

    @constraintref op_cost_calc[1:length(RESOURCES)];
        
    for i in RESOURCES                                                                                                         
     op_cost_calc[RESOURCESD[i]] = @constraint(blk, C_op[i] == sum(c_op[i,t]*F_Mult_t[i,t]*t_op[t] for t in PERIODS)) 
    end                                                                                                                


    # 1.25

    @constraint(blk, hydro_dams_shift[t=PERIODS], Storage_In["PUMPED_HYDRO","ELECTRICITY",t] <= (F_Mult_t["HYDRO_DAM",t] + F_Mult_t["NEW_HYDRO_DAM",t]));

    # 1.27 linealizado

    @constraint(blk, max_dhn_heat_demand[t=PERIODS], Max_Heat_Demand_DHN >= End_Uses["HEAT_LOW_T_DHN",t]+Losses["HEAT_LOW_T_DHN",t]);

    @constraint(blk, peak_dhn, sum(F_Mult[TECHNOLOGIESD[j]] for j in TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DHN"]) >= peak_dhn_factor*Max_Heat_Demand_DHN);

    # 1.31

    ### CONSTRAINTS  DEMAND ###

    @constraintref end_uses_t[1:length(LAYERS),1:length(PERIODS)]

    for l in LAYERS
        if l == "ELECTRICITY"
            for t in PERIODS
                end_uses_t[LAYERSD[l],t] = @constraint(blk, End_Uses[l,t] == M_end_uses_input[l][s]/total_time + M_end_uses_input["LIGHTING"][s]*lighting_month[t]/t_op[t]+Losses[l,t]);
            end
        elseif l == "HEAT_LOW_T_DHN"
            for t in PERIODS
                end_uses_t[LAYERSD[l],t] = @constraint(blk, End_Uses[l,t] == (M_end_uses_input["HEAT_LOW_T_HW"][s]/total_time + M_end_uses_input["HEAT_LOW_T_SH"][s]*heating_month[t]/t_op[t])*Share_Heat_Dhn);
            end
        elseif l == "HEAT_LOW_T_DECEN"
            for t in PERIODS
                end_uses_t[LAYERSD[l],t] = @constraint(blk, End_Uses[l,t] == (M_end_uses_input["HEAT_LOW_T_HW"][s]/total_time + M_end_uses_input["HEAT_LOW_T_SH"][s]*heating_month[t]/t_op[t])*(1 - Share_Heat_Dhn))
            end
        elseif l == "MOB_PUBLIC"
            for t in PERIODS
                end_uses_t[LAYERSD[l],t] = @constraint(blk, End_Uses[l,t] == (M_end_uses_input["MOBILITY_PASSENGER"][s] / total_time) * Share_Mobility_Public)
            end
        elseif l == "MOB_PRIVATE"
            for t in PERIODS
                end_uses_t[LAYERSD[l],t] = @constraint(blk, End_Uses[l,t] == (M_end_uses_input["MOBILITY_PASSENGER"][s] / total_time) * (1 - Share_Mobility_Public))
            end
        elseif l == "MOB_FREIGHT_RAIL"
            for t in PERIODS
                end_uses_t[LAYERSD[l],t] = @constraint(blk, End_Uses[l,t] == (M_end_uses_input["MOBILITY_FREIGHT"][s] / total_time) * Share_Freight_Train)
            end
        elseif l == "MOB_FREIGHT_ROAD"
            for t in PERIODS
                end_uses_t[LAYERSD[l],t] = @constraint(blk, End_Uses[l,t] == (M_end_uses_input["MOBILITY_FREIGHT"][s] / total_time) * (1 - Share_Freight_Train))
            end
        elseif l == "HEAT_HIGH_T"
            for t in PERIODS
                end_uses_t[LAYERSD[l],t] = @constraint(blk, End_Uses[l,t] == M_end_uses_input[l][s] / total_time)
            end
        else
            for t in PERIODS
                end_uses_t[LAYERSD[l],t] = @constraint(blk, End_Uses[l,t] == 0)
            end
        end
    end                                                                                                                


end
