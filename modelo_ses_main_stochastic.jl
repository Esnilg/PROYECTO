using JuMP, Dsp

include("parametros_inciertos.jl")

prob = ones(NS) / NS; # probabilities

# JuMP model

modelo = Model(NS)

# var I stage

@variable(modelo,TotalCost >= 0);
@variable(modelo,C_inv[TECHNOLOGIES] >=0);
@variable(modelo,C_maint[TECHNOLOGIES] >=0);
@variable(modelo,GWP_constr[TECHNOLOGIES] >= 0);
#@variable(modelo,F_Mult[i in TECHNOLOGIES], lowerbound=f_min[i], upperbound=f_max[i])
@variable(modelo,f_min[i] <= F_Mult[i=TECHNOLOGIES] <= f_max[i]);
@variable(modelo,Number_Of_Units[TECHNOLOGIES] >=0); # ENTERA
@variable(modelo,share_mobility_public_min <= Share_Mobility_Public <= share_mobility_public_max);
@variable(modelo,share_freight_train_min <= Share_Freight_Train <= share_freight_train_max);
@variable(modelo,share_heat_dhn_min <= Share_Heat_Dhn <= share_heat_dhn_max);
@variable(modelo, 0 <= Y_Solar_Backup[TECHNOLOGIES] <= 1); # BINARIA


### OBJECTIVE FUNCTION ###

@objective(modelo, :Min, TotalCost);

@constraint(modelo, totalcost_cal, TotalCost == sum(tau[i]*C_inv[i] + C_maint[i] for i in TECHNOLOGIES));

# const I stage

# 1.3

@constraintref investment_cost_calc[1:length(TECHNOLOGIES)] 
                                                                                                                
for i in TECHNOLOGIES                                                                                             
    investment_cost_calc[TECHNOLOGIESD[i]] = @constraint(modelo, C_inv[i] == c_inv[i]*F_Mult[i]) 
end                                                                                                                

# 1.4
                                                                                                                
@constraintref main_cost_calc[1:length(TECHNOLOGIES)] 
                                                                                                                
for i in TECHNOLOGIES                                                                                                          
    main_cost_calc[TECHNOLOGIESD[i]] = @constraint(modelo, C_maint[i] == c_maint[i] * F_Mult[i]) 
end                                                                                                                

# 1.5

@constraintref gwp_constr_calc[1:length(TECHNOLOGIES)];

for i in TECHNOLOGIES
    gwp_constr_calc[TECHNOLOGIESD[i]] = @constraint(modelo, GWP_constr[i] == gwp_constr[i]*F_Mult[i]);
end

# 1.6 esta en la deficion de variable y no como restriccion esto es porque no lo soporta JuMP

#@constraintref size_limit[1:length(TECHNOLOGIES)];

#for i in TECHNOLOGIES
#    size_limit[TECHNOLOGIESD[i]] = @constraint(modelo, f_min[i] <= F_Mult[i] <= f_max[i]);
#end

# 1.7 

@constraintref number_of_units[1:length(setdiff(TECHNOLOGIES,INFRASTRUCTURE))];

for i in setdiff(TECHNOLOGIES,INFRASTRUCTURE)
    number_of_units[TECHNOLOGIESdiffINFRASTRUCTURED[i]] = @constraint(modelo, Number_Of_Units[i] == F_Mult[i]/ref_size[i]);
end

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

@constraint(modelo, op_strategy_decen_2, sum(Y_Solar_Backup[i] for i in TECHNOLOGIES) <= 1);

# requisito

@constraint(modelo, F_Mult["NUCLEAR"] == 0.0);


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
    @variable(blk,Max_Heat_Demand_DHN >= 0)


    ### OBJECTIVE FUNCTION ###

    @objective(blk, :Min, TotalCost_stoch);

    @constraint(blk, totalcost_cal_stoch, TotalCost_stoch == sum(C_op[j] for j in RESOURCES));

    # 1.8

    @constraintref capacity_factor_t[1:length(TECHNOLOGIES),1:length(PERIODS)]

    for i in TECHNOLOGIES, t in PERIODS
     capacity_factor_t[TECHNOLOGIESD[i],t] = @constraint(blk, F_Mult_t[i,t] <= F_Mult[i]*c_p_t[i,t]);
    end

    # 1.9

    @constraintref capacity_factor[1:length(TECHNOLOGIES)]

    for i in TECHNOLOGIES
     capacity_factor[TECHNOLOGIESD[i]] = @constraint(blk, sum(F_Mult_t[i,t]*t_op[t] for t in PERIODS) <= F_Mult[i]*c_p[i]*total_time);
    end

    # 1.10

    @constraintref op_cost_calc[1:length(RESOURCES)] 
    
    #for i in RESOURCES, t in PERIODS
    #    if in(i,defparam_c_op)
    #        c_op[i,t] = M_c_op[i][s];
    #    end
    #end
    
    for i in RESOURCES                                                                                                         
     op_cost_calc[RESOURCESD[i]] = @constraint(blk, C_op[i] == sum(c_op[i,t]*F_Mult_t[i,t]*t_op[t] for t in PERIODS)) 
    end                                                                                                                
    
    # 1.11

    @constraintref gwp_op_calc[1:length(RESOURCES)];

    for i in RESOURCES
     gwp_op_calc[RESOURCESD[i]] = @constraint(blk, GWP_op[i] == gwp_op[i]*sum(t_op[t]*F_Mult_t[i, t] for t in PERIODS));
    end

    # 1.12

    @constraintref resource_availability[1:length(RESOURCES)]

    for i in RESOURCES
     resource_availability[RESOURCESD[i]] = @constraint(blk, sum(F_Mult_t[i,t]*t_op[t] for t in PERIODS) <= avail[i])
    end

    # 1.13

    @constraintref layer_balance[1:length(LAYERS),1:length(PERIODS)]

    for l in LAYERS, t in PERIODS
     if l == "HEAT_LOW_T_DHN"
      layer_balance[LAYERSD[l],t] = @constraint(blk, 0.0 == sum(layers_in_out[i,l]*F_Mult_t[i,t] for i in setdiff(union(RESOURCES,TECHNOLOGIES),STORAGE_TECH)) + sum(Storage_Out[j,l,t] - Storage_In[j,l,t] for j in STORAGE_TECH)- End_Uses[l,t] - Losses[l,t])
     else 
      layer_balance[LAYERSD[l],t] = @constraint(blk, 0.0 == sum(layers_in_out[i,l]*F_Mult_t[i,t] for i in setdiff(union(RESOURCES,TECHNOLOGIES),STORAGE_TECH)) + sum(Storage_Out[j,l,t] - Storage_In[j,l,t] for j in STORAGE_TECH)- End_Uses[l,t])  
    end
    end

    # 1.14

    @constraintref storage_level[1:length(STORAGE_TECH),1:length(PERIODS)]

    for i in STORAGE_TECH, t in PERIODS
     if t == 1
        storage_level[STORAGE_TECHD[i],t] = @constraint(blk, F_Mult_t[i, t] == F_Mult_t[i,length(PERIODS)] + (sum(Storage_In[i, l, t]*storage_eff_in[i, l] for l in LAYERS if  storage_eff_in[i,l] > 0) - sum(Storage_Out[i, l, t]/storage_eff_out[i,l] for l in LAYERS if storage_eff_out[i,l] > 0))*t_op[t])
     else
        storage_level[STORAGE_TECHD[i],t] = @constraint(blk, F_Mult_t[i, t] == F_Mult_t[i,t-1] + (sum(Storage_In[i, l, t] * storage_eff_in[i,l] for l in LAYERS if storage_eff_in[i,l] > 0) - sum(Storage_Out[i,l,t]/storage_eff_out[i,l] for l in LAYERS if  storage_eff_out[i,l] > 0))*t_op[t])
     end
    end

    # 1.15

    @constraintref storage_layer_in[1:length(STORAGE_TECH),1:length(LAYERS),1:length(PERIODS)]

    for i in STORAGE_TECH, l in LAYERS, t in PERIODS 
     storage_layer_in[STORAGE_TECHD[i],LAYERSD[l],t] = @constraint(blk, Storage_In[i,l,t]*(ceil(storage_eff_in[i,l]) - 1) == 0.0)
    end

    # 1.16

    @constraintref storage_layer_out[1:length(STORAGE_TECH),1:length(LAYERS),1:length(PERIODS)]

    for i in STORAGE_TECH, l in LAYERS, t in PERIODS 
     storage_layer_out[STORAGE_TECHD[i],LAYERSD[l],t] = @constraint(blk, Storage_Out[i,l,t]*(ceil(storage_eff_out[i,l]) - 1) == 0.0)
    end

    # 1.17 linealizado

    @constraintref storage_no_transfer_1[1:length(STORAGE_TECH),1:length(PERIODS)]

    for i in STORAGE_TECH, t in PERIODS
     storage_no_transfer_1[STORAGE_TECHD[i],t] = @constraint(blk, sum(Storage_In[i,l,t]*storage_eff_in[i,l] for l in LAYERS if storage_eff_in[i,l] > 0)*t_op[t]/f_max[i] <= Y_Sto_In[i,t])
    end

    @constraintref storage_no_transfer_2[1:length(STORAGE_TECH),1:length(PERIODS)]

    for i in STORAGE_TECH, t in PERIODS
     storage_no_transfer_2[STORAGE_TECHD[i],t] = @constraint(blk, sum(Storage_Out[i,l,t]*storage_eff_out[i,l] for l in LAYERS if storage_eff_out[i,l] > 0)*t_op[t]/f_max[i] <= Y_Sto_Out[i,t])
    end

    @constraintref storage_no_transfer_3[1:length(STORAGE_TECH),1:length(PERIODS)]

    for i in STORAGE_TECH, t in PERIODS
     storage_no_transfer_3[STORAGE_TECHD[i],t] = @constraint(blk, Y_Sto_In[i,t] + Y_Sto_Out[i,t] <= 1)
    end

    # 1.18

    @constraintref network_losses[1:length(END_USES_TYPES),1:length(PERIODS)]
                                        
    for i in END_USES_TYPES, t in PERIODS
     network_losses[END_USES_TYPESD[i],t] = @constraint(blk, Losses[i,t] == sum(layers_in_out[j,i]*F_Mult_t[j,t] for j in setdiff(union(RESOURCES,TECHNOLOGIES),STORAGE_TECH) if layers_in_out[j, i] > 0)*loss_coeff[i])
    end



    # 1.21
                                                                                                                    
    @constraint(blk, totalGWP_calc, TotalGWP == sum(GWP_constr[i]/lifetime[i] for i in TECHNOLOGIES) + sum(GWP_op[j] for j in RESOURCES));

    # 1.22

    vecauxiliar = [1:length(TECHNOLOGIES_OF_END_USES_TYPE[i]) for i in END_USES_TYPES];                                                                                                                
                                                                                                                
    @constraintref f_max_perc[1:length(END_USES_TYPES),1:14] # elijo vecauxiliar[1] porque tiene mayor dimension
                                                                                                                
    for i in END_USES_TYPES
     k = 1
     for j in TECHNOLOGIES_OF_END_USES_TYPE[i]                                                                                                            
        f_max_perc[END_USES_TYPESD[i],k] = @constraint(blk, sum(F_Mult_t[j, t]*t_op[t] for t in PERIODS) <= fmax_perc[j]*sum(F_Mult_t[j2,t2]*t_op[t2] for j2 in TECHNOLOGIES_OF_END_USES_TYPE[i], t2 in PERIODS))
        k +=1;
     end                                                           
    end                                                                                                            

    @constraintref f_min_perc[1:length(END_USES_TYPES),1:14] # elijo vecauxiliar[1] porque tiene mayor dimension
                                                                                                                
    for i in END_USES_TYPES
     k = 1
     for j in TECHNOLOGIES_OF_END_USES_TYPE[i]                                                                                                                
        f_min_perc[END_USES_TYPESD[i],k] = @constraint(blk, sum(F_Mult_t[j, t]*t_op[t] for t in PERIODS) >= fmin_perc[j]*sum(F_Mult_t[j2,t2]*t_op[t2] for j2 in TECHNOLOGIES_OF_END_USES_TYPE[i], t2 in PERIODS))
        k +=1;
     end                                                           
    end                                                                                                            

    # 1.23

    @constraintref op_strategy_mob_private[1:length(op_strategy_mob_privateD),1:length(PERIODS)]
                                                                                                                
    for i in union(TECHNOLOGIES_OF_END_USES_CATEGORY["MOBILITY_PASSENGER"],TECHNOLOGIES_OF_END_USES_CATEGORY["MOBILITY_FREIGHT"]), t in PERIODS
     op_strategy_mob_private[op_strategy_mob_privateD[i],t] = @constraint(blk, F_Mult_t[i,t] >= sum(F_Mult_t[i,t2]*t_op[t2]/total_time for  t2 in PERIODS) ) 
    end

    # 1.25                                      
                                                                                                                
    @constraint(blk, hydro_dams_shift[t=PERIODS], Storage_In["PUMPED_HYDRO","ELECTRICITY",t] <= (F_Mult_t["HYDRO_DAM",t] + F_Mult_t["NEW_HYDRO_DAM",t]))

    # 1.27 linealizado

    @constraint(blk, max_dhn_heat_demand[t=PERIODS], Max_Heat_Demand_DHN >= End_Uses["HEAT_LOW_T_DHN",t]+Losses["HEAT_LOW_T_DHN",t])
                                                                                                                          
    @constraint(blk, peak_dhn, sum(F_Mult[j] for j in TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DHN"]) >= peak_dhn_factor*Max_Heat_Demand_DHN)                                                                                                                

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

