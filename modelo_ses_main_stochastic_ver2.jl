using JuMP, Dsp

include("parametros_inciertos.jl")

prob = ones(NS) / NS; # probabilities

# JuMP model

modelo = 0;
modelo = Model(NS)

# var I stage

@variable(modelo,TotalCost >= 0)
@variable(modelo,C_inv[TECHNOLOGIES] >=0)
@variable(modelo,C_maint[TECHNOLOGIES] >=0)
@variable(modelo,GWP_constr[TECHNOLOGIES] >= 0)
#@variable(modelo,F_Mult[i in TECHNOLOGIES], lowerbound=f_min[i], upperbound=f_max[i])
@variable(modelo,f_min[i] <= F_Mult[i=TECHNOLOGIES] <= f_max[i])
@variable(modelo,Number_Of_Units[TECHNOLOGIES] >=0) # ENTERA
@variable(modelo, 0 <= Y_Solar_Backup[TECHNOLOGIES] <= 1) # BINARIA

@variable(modelo,share_mobility_public_min <= Share_Mobility_Public <= share_mobility_public_max)
@variable(modelo,share_freight_train_min <= Share_Freight_Train <= share_freight_train_max)
@variable(modelo,share_heat_dhn_min <= Share_Heat_Dhn <= share_heat_dhn_max)



### OBJECTIVE FUNCTION ###

@objective(modelo, Min, TotalCost)

@constraint(modelo, totalcost_cal, TotalCost == sum(tau[i]*C_inv[i] + C_maint[i] for i in TECHNOLOGIES))

# const I stage

# 1.3
@constraint(modelo, investment_cost_calc[i=TECHNOLOGIES],C_inv[i] == c_inv[i]*F_Mult[i])

# 1.4
@constraint(modelo, main_cost_calc[i=TECHNOLOGIES],C_maint[i] == c_maint[i] * F_Mult[i])

# 1.5
@constraint(modelo, gwp_constr_calc[i=TECHNOLOGIES],GWP_constr[i] == gwp_constr[i]*F_Mult[i])

# 1.6 esta en la deficion de variable y no como restriccion esto es porque no lo soporta JuMP

#@constraintref size_limit[1:length(TECHNOLOGIES)];

#for i in TECHNOLOGIES
#    size_limit[TECHNOLOGIESD[i]] = @constraint(modelo, f_min[i] <= F_Mult[i] <= f_max[i])
#end

# 1.7 
@constraint(modelo, number_of_units[i=setdiff(TECHNOLOGIES,INFRASTRUCTURE)],Number_Of_Units[i] == F_Mult[i]/ref_size[i])

# 1.24
@constraint(modelo, storage_level_hydro_dams, F_Mult["PUMPED_HYDRO"] <= f_max["PUMPED_HYDRO"] * (F_Mult["NEW_HYDRO_DAM"] - f_min["NEW_HYDRO_DAM"])/(f_max["NEW_HYDRO_DAM"] - f_min["NEW_HYDRO_DAM"]))

# 1.26
@constraint(modelo, extra_dhn, F_Mult["DHN"] == sum(F_Mult[j] for j in TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DHN"]))

# 1.28
@constraint(modelo, extra_grid, F_Mult["GRID"] == 1 + (9400 /c_inv["GRID"]) * (F_Mult["WIND"] + F_Mult["PV"])/(f_max["WIND"] + f_max["PV"]))

# 1.29 linealizacion
@constraint(modelo, extra_power2gas_1, F_Mult["POWER2GAS_3"] >= F_Mult["POWER2GAS_1"])
@constraint(modelo, extra_power2gas_2, F_Mult["POWER2GAS_3"] >= F_Mult["POWER2GAS_2"])

# 1.30 no esta en la tesis

@constraint(modelo, extra_efficiency, F_Mult["EFFICIENCY"] == 1/(1 + i_rate))

# 1.19
@constraint(modelo, op_strategy_decen_2, sum(Y_Solar_Backup[i] for i in TECHNOLOGIES) <= 1)

# requisito
@constraint(modelo, F_Mult["NUCLEAR"] == 0.0)


# II STAGE


for s in blockids()
    blk = Model(modelo, s, prob[s])

    @variable(blk,TotalCost_stoch >= 0)
    @variable(blk,End_Uses[LAYERS,PERIODS] >=0)
    @variable(blk,F_Mult_t[union(RESOURCES,TECHNOLOGIES),PERIODS] >=0)
    @variable(blk,C_op[RESOURCES] >=0)
    @variable(blk,Storage_In[STORAGE_TECH,LAYERS,PERIODS] >=0)
    @variable(blk,Storage_Out[STORAGE_TECH,LAYERS,PERIODS] >=0)
    @variable(blk,Losses[END_USES_TYPES,PERIODS] >= 0)
    @variable(blk,GWP_op[RESOURCES] >= 0)
    @variable(blk,TotalGWP >= 0)

    # var auxiliar
    @variable(blk,X_Solar_Backup_Aux[setdiff(TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DECEN"],["DEC_SOLAR"]),PERIODS] >= 0)

    # Linearization of Eq. 1.14
    #@variable(blk,0 <= Y_Sto_In[STORAGE_TECH,PERIODS] <= 1) # BINARIAS
    #@variable(blk,0 <= Y_Sto_Out[STORAGE_TECH,PERIODS] <= 1) # BINARIAS

    # [Eq. 1.27] Calculation of max heat demand in DHN 
    @variable(blk,Max_Heat_Demand_DHN >= 0)

    ### OBJECTIVE FUNCTION ###

    @objective(blk, Min, TotalCost_stoch)

    @constraint(blk, totalcost_cal_stoch, TotalCost_stoch == sum(C_op[j] for j in RESOURCES))

    # 1.8
    @constraint(blk, capacity_factor_t[i=TECHNOLOGIES,t=PERIODS], F_Mult_t[i,t] <= F_Mult[i]*c_p_t[i,t])

    # 1.9
    @constraint(blk, capacity_factor[i=TECHNOLOGIES],sum(F_Mult_t[i,t]*t_op[t] for t in PERIODS) <= F_Mult[i]*c_p[i]*total_time)

    # 1.10
    
    #for i in RESOURCES, t in PERIODS
    #    if in(i,defparam_c_op)
    #        c_op[i,t] = M_c_op[i][s];
    #    end
    #end
    
    @constraint(blk, op_cost_calc[i=RESOURCES],C_op[i] == sum(c_op[i,t]*F_Mult_t[i,t]*t_op[t] for t in PERIODS))

    # 1.11
    @constraint(blk, gwp_op_calc[i=RESOURCES],GWP_op[i] == gwp_op[i]*sum(t_op[t]*F_Mult_t[i, t] for t in PERIODS))

    # 1.12
    @constraint(blk, resource_availability[i=RESOURCES],sum(F_Mult_t[i,t]*t_op[t] for t in PERIODS) <= avail[i])

    # 1.13
    EXP = Set(["HEAT_LOW_T_DHN"])
    @constraint(blk, layer_balance[l=LAYERS,t=PERIODS], 0.0 == sum(layers_in_out[i,l]*F_Mult_t[i,t] for i in setdiff(union(RESOURCES,TECHNOLOGIES),STORAGE_TECH)) + sum(Storage_Out[j,l,t] - Storage_In[j,l,t] for j in STORAGE_TECH) - End_Uses[l,t] - (in(l,EXP)?Losses[l,t]:0))

    # 1.14
    EXP = Set(1)
    @constraint(blk, storage_level[i=STORAGE_TECH,t=PERIODS],F_Mult_t[i, t] == (in(t,EXP)?F_Mult_t[i,length(PERIODS)]:F_Mult_t[i,t-1])  + (sum(Storage_In[i, l, t]*storage_eff_in[i, l] for l in LAYERS if  storage_eff_in[i,l] > 0) - sum(Storage_Out[i, l, t]/storage_eff_out[i,l] for l in LAYERS if storage_eff_out[i,l] > 0))*t_op[t])

    # 1.15
    @constraint(blk, storage_layer_in[i=STORAGE_TECH,l=LAYERS,t=PERIODS],Storage_In[i,l,t]*(ceil(storage_eff_in[i,l]) - 1) == 0.0)

    # 1.16
    @constraint(blk, storage_layer_out[i=STORAGE_TECH,l=LAYERS,t=PERIODS],Storage_Out[i,l,t]*(ceil(storage_eff_out[i,l]) - 1) == 0.0)

    # 1.17 linealizado
    #@constraint(blk, storage_no_transfer_1[i=STORAGE_TECH,t=PERIODS],sum(Storage_In[i,l,t]*storage_eff_in[i,l] for l in LAYERS if storage_eff_in[i,l] > 0)*t_op[t]/f_max[i] <= Y_Sto_In[i,t])
    #@constraint(blk, storage_no_transfer_2[i=STORAGE_TECH,t=PERIODS],sum(Storage_Out[i,l,t]*storage_eff_out[i,l] for l in LAYERS if storage_eff_out[i,l] > 0)*t_op[t]/f_max[i] <= Y_Sto_Out[i,t])
    #@constraint(blk, storage_no_transfer_3[i=STORAGE_TECH,t=PERIODS],Y_Sto_In[i,t] + Y_Sto_Out[i,t] <= 1)

    # 1.18
                                        
    @constraint(blk, network_losses[i=END_USES_TYPES,t=PERIODS],Losses[i,t] == sum(layers_in_out[j,i]*F_Mult_t[j,t] for j in setdiff(union(RESOURCES,TECHNOLOGIES),STORAGE_TECH) if layers_in_out[j, i] > 0)*loss_coeff[i])

    # 1.19 Linealizado
    @constraint(blk, op_strategy_decen_1_linear_1[i=setdiff(TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DECEN"],["DEC_SOLAR"]),t=PERIODS],F_Mult_t[i,t] + X_Solar_Backup_Aux[i,t] >= sum(F_Mult_t[i,t2] * t_op[t2] for t2 in PERIODS)*((M_end_uses_input["HEAT_LOW_T_HW"][s]/total_time + M_end_uses_input["HEAT_LOW_T_SH"][s]*heating_month[t]/t_op[t])/(M_end_uses_input["HEAT_LOW_T_HW"][s] + M_end_uses_input["HEAT_LOW_T_SH"][s])))
    @constraint(blk, op_strategy_decen_1_linear_2[i=setdiff(TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DECEN"],["DEC_SOLAR"]),t=PERIODS],X_Solar_Backup_Aux[i,t] <= f_max["DEC_SOLAR"]*Y_Solar_Backup[i])
    @constraint(blk, op_strategy_decen_1_linear_3[i=setdiff(TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DECEN"],["DEC_SOLAR"]),t=PERIODS],X_Solar_Backup_Aux[i,t] <= F_Mult_t["DEC_SOLAR",t])
    @constraint(blk, op_strategy_decen_1_linear_4[i=setdiff(TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DECEN"],["DEC_SOLAR"]),t=PERIODS],X_Solar_Backup_Aux[i,t] >= F_Mult_t["DEC_SOLAR",t] - (1 - Y_Solar_Backup[i])*f_max["DEC_SOLAR"])

    # 1.21                                                                                                                    
    @constraint(blk, totalGWP_calc, TotalGWP == sum(GWP_constr[i]/lifetime[i] for i in TECHNOLOGIES) + sum(GWP_op[j] for j in RESOURCES))

    # 1.22
    @constraint(blk, f_max_perc[i=END_USES_TYPES,j=TECHNOLOGIES_OF_END_USES_TYPE[i]],sum(F_Mult_t[j, t]*t_op[t] for t in PERIODS) <= fmax_perc[j]*sum(F_Mult_t[j2,t2]*t_op[t2] for j2 in TECHNOLOGIES_OF_END_USES_TYPE[i], t2 in PERIODS)) 
    @constraint(blk, f_min_perc[i=END_USES_TYPES,j=TECHNOLOGIES_OF_END_USES_TYPE[i]],sum(F_Mult_t[j, t]*t_op[t] for t in PERIODS) >= fmin_perc[j]*sum(F_Mult_t[j2,t2]*t_op[t2] for j2 in TECHNOLOGIES_OF_END_USES_TYPE[i], t2 in PERIODS))

    # 1.23
    @constraint(blk, op_strategy_mob_private[i=union(TECHNOLOGIES_OF_END_USES_CATEGORY["MOBILITY_PASSENGER"],TECHNOLOGIES_OF_END_USES_CATEGORY["MOBILITY_FREIGHT"]),t=PERIODS], F_Mult_t[i,t] >= sum(F_Mult_t[i,t2]*t_op[t2]/total_time for  t2 in PERIODS))

    # 1.25                                                                                                                                                      
    @constraint(blk, hydro_dams_shift[t=PERIODS], Storage_In["PUMPED_HYDRO","ELECTRICITY",t] <= (F_Mult_t["HYDRO_DAM",t] + F_Mult_t["NEW_HYDRO_DAM",t]))

    # 1.27 linealizado
    @constraint(blk, max_dhn_heat_demand[t=PERIODS], Max_Heat_Demand_DHN >= End_Uses["HEAT_LOW_T_DHN",t]+Losses["HEAT_LOW_T_DHN",t])                                                                                                                
    @constraint(blk, peak_dhn, sum(F_Mult[j] for j in TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DHN"]) >= peak_dhn_factor*Max_Heat_Demand_DHN)

    # 1.31

    ### CONSTRAINTS  DEMAND ###

    @constraint(blk, end_uses_t1[l=LAYERS,t=PERIODS; l=="ELECTRICITY"], End_Uses[l,t] == M_end_uses_input[l][s]/total_time + M_end_uses_input["LIGHTING"][s]*lighting_month[t]/t_op[t]+Losses[l,t])
    @constraint(blk, end_uses_t2[l=LAYERS,t=PERIODS; l=="HEAT_LOW_T_DHN"], End_Uses[l,t] == (M_end_uses_input["HEAT_LOW_T_HW"][s]/total_time + M_end_uses_input["HEAT_LOW_T_SH"][s]*heating_month[t]/t_op[t])*Share_Heat_Dhn)
    @constraint(blk, end_uses_t3[l=LAYERS,t=PERIODS; l=="HEAT_LOW_T_DECEN"], End_Uses[l,t] == (M_end_uses_input["HEAT_LOW_T_HW"][s]/total_time + M_end_uses_input["HEAT_LOW_T_SH"][s]*heating_month[t]/t_op[t])*(1 - Share_Heat_Dhn))
    @constraint(blk, end_uses_t4[l=LAYERS,t=PERIODS; l=="MOB_PUBLIC"], End_Uses[l,t] == (M_end_uses_input["MOBILITY_PASSENGER"][s] / total_time) * Share_Mobility_Public)
    @constraint(blk, end_uses_t5[l=LAYERS,t=PERIODS; l=="MOB_PRIVATE"], End_Uses[l,t] == (M_end_uses_input["MOBILITY_PASSENGER"][s] / total_time) * (1 - Share_Mobility_Public))
    @constraint(blk, end_uses_t6[l=LAYERS,t=PERIODS; l=="MOB_FREIGHT_RAIL"], End_Uses[l,t] == (M_end_uses_input["MOBILITY_FREIGHT"][s] / total_time) * Share_Freight_Train)
    @constraint(blk, end_uses_t7[l=LAYERS,t=PERIODS; l=="MOB_FREIGHT_ROAD"], End_Uses[l,t] == (M_end_uses_input["MOBILITY_FREIGHT"][s] / total_time) * (1 - Share_Freight_Train))
    @constraint(blk, end_uses_t8[l=LAYERS,t=PERIODS; l=="HEAT_HIGH_T"], End_Uses[l,t] == M_end_uses_input[l][s] / total_time)
    EXP= setdiff(LAYERS,Set(["ELECTRICITY","HEAT_LOW_T_DHN","HEAT_LOW_T_DECEN","MOB_PUBLIC","MOB_PRIVATE","MOB_FREIGHT_RAIL","MOB_FREIGHT_ROAD","HEAT_HIGH_T"]));
    @constraint(blk, end_uses_t9[l=EXP,t=PERIODS], End_Uses[l,t] == 0)

end

