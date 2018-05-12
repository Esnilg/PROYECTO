using JuMP, Dsp

include("parametros_inciertos.jl")

prob = ones(NS) / NS; # probabilities

# JuMP model

modelo = 0;
modelo = Model(NS)

# var I stage

@variable(modelo,TotalCost >= 0.0)
@variable(modelo,C_inv[TECHNOLOGIES] >=0.0)
@variable(modelo,C_maint[TECHNOLOGIES] >=0.0)
@variable(modelo,GWP_constr[TECHNOLOGIES] >= 0.0)
@variable(modelo,f_min[i] <= F_Mult[i=TECHNOLOGIES] <= f_max[i])
@variable(modelo,Number_Of_Units[TECHNOLOGIES] >=0.0) # ENTERA
@variable(modelo, 0.0 <= Y_Solar_Backup[TECHNOLOGIES] <= 1.0) # BINARIA
@variable(modelo,share_mobility_public_min <= Share_Mobility_Public <= share_mobility_public_max)
@variable(modelo,share_freight_train_min <= Share_Freight_Train <= share_freight_train_max)
@variable(modelo,share_heat_dhn_min <= Share_Heat_Dhn <= share_heat_dhn_max)

### OBJECTIVE FUNCTION ###

@objective(modelo, Min, TotalCost)

@constraint(modelo, TotalCost == sum(tau[i] * C_inv[i] for i=TECHNOLOGIES) + sum(C_maint[i] for i=TECHNOLOGIES))

# const I stage

for i = TECHNOLOGIES
    @constraint(modelo, C_inv[i] == c_inv[i] * F_Mult[i])			# 1.3
    @constraint(modelo, C_maint[i] == c_maint[i] * F_Mult[i])		# 1.4
#   @constraint(modelo, GWP_constr[i] == gwp_constr[i]*F_Mult[i])	# 1.5
end

# 1.6 cotas

# 1.7 
for i = setdiff(TECHNOLOGIES,INFRASTRUCTURE)
    @constraint(modelo, Number_Of_Units[i] == F_Mult[i] / ref_size[i])
end

# 1.24
@constraint(modelo, F_Mult["PUMPED_HYDRO"] <= f_max["PUMPED_HYDRO"] * (F_Mult["NEW_HYDRO_DAM"] - f_min["NEW_HYDRO_DAM"])/(f_max["NEW_HYDRO_DAM"] - f_min["NEW_HYDRO_DAM"]))

# 1.26
@constraint(modelo, F_Mult["DHN"] == sum(F_Mult[j] for j in TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DHN"]))

# 1.28
@constraint(modelo, F_Mult["GRID"] == 1 + (9400 / c_inv["GRID"]) * (F_Mult["WIND"] + F_Mult["PV"]) / (f_max["WIND"] + f_max["PV"]))

# 1.29 linealizacion
@constraint(modelo, F_Mult["POWER2GAS_3"] >= F_Mult["POWER2GAS_1"])
@constraint(modelo, F_Mult["POWER2GAS_3"] >= F_Mult["POWER2GAS_2"])

# 1.30 no esta en la tesis

@constraint(modelo, F_Mult["EFFICIENCY"] == 1/(1 + i_rate))

# 1.19
@constraint(modelo, sum(Y_Solar_Backup[i] for i in TECHNOLOGIES) <= 1)

# requisito
@constraint(modelo, F_Mult["NUCLEAR"] == 0.0)

# II STAGE


for s in blockids()

    blk = Model(modelo, s, prob[s])

    @variable(blk,TotalCoststoch >= 0.0)
    @variable(blk,F_Mult_t[union(RESOURCES,TECHNOLOGIES),PERIODS] >=0.0)
    @variable(blk,End_Uses[LAYERS,PERIODS] >=0.0)
    @variable(blk,C_op[RESOURCES] >=0.0)
    @variable(blk,Storage_In[STORAGE_TECH,LAYERS,PERIODS] >=0.0)
    @variable(blk,Storage_Out[STORAGE_TECH,LAYERS,PERIODS] >=0.0)
    @variable(blk,Losses[END_USES_TYPES,PERIODS] >= 0.0)
#    @variable(blk,GWP_op[RESOURCES] >= 0.0)
#    @variable(blk,TotalGWP >= 0.0)

    # var auxiliar
    @variable(blk,X_Solar_Backup_Aux[setdiff(TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DECEN"],["DEC_SOLAR"]),PERIODS] >= 0)

    # Linearization of Eq. 1.17
    #@variable(blk,0 <= Y_Sto_In[STORAGE_TECH,PERIODS] <= 1) # BINARIAS
    #@variable(blk,0 <= Y_Sto_Out[STORAGE_TECH,PERIODS] <= 1) # BINARIAS

    # [Eq. 1.27] Calculation of max heat demand in DHN 
    @variable(blk,Max_Heat_Demand_DHN >= 0.0)

    ### OBJECTIVE FUNCTION ###

    @objective(blk, :Min, TotalCoststoch)

    @constraint(blk, TotalCoststoch == sum(C_op[i] for i=RESOURCES))

    # 1.8
    for i=TECHNOLOGIES,t=PERIODS
        @constraint(blk, F_Mult_t[i,t] <= F_Mult[i] * c_p_t[i,t])
    end

    # 1.9
    for i=TECHNOLOGIES
        @constraint(blk, sum(F_Mult_t[i,t]*t_op[t] for t=PERIODS) <= F_Mult[i] * c_p[i] * total_time)
    end

    # 1.10
    for i=RESOURCES
        @constraint(blk, C_op[i] == sum(c_op[i,t] * F_Mult_t[i,t] * t_op[t] for t=PERIODS))
    end
    
    for i=RESOURCES
#       @constraint(blk, GWP_op[i] == gwp_op[i]*sum(t_op[t]*F_Mult_t[i, t] for t in PERIODS))	# 1.11
        @constraint(blk, sum(F_Mult_t[i,t] * t_op[t] for t=PERIODS) <= avail[i])			# 1.12
    end

    # 1.13
    EXP = ["HEAT_LOW_T_DHN"]
    for l=LAYERS,t=PERIODS
        @constraint(blk, 0.0 == sum(layers_in_out[i,l] * F_Mult_t[i,t] for i in setdiff(union(RESOURCES,TECHNOLOGIES),STORAGE_TECH)) + sum(Storage_Out[j,l,t] - Storage_In[j,l,t] for j in STORAGE_TECH) - End_Uses[l,t] - (in(l,EXP)?Losses[l,t]:0.0))
    end

    # 1.14
    EXP = [1]
    for i=STORAGE_TECH,t=PERIODS
        @constraint(blk, F_Mult_t[i, t] == (in(t,EXP)?F_Mult_t[i,length(PERIODS)]:F_Mult_t[i,t-1])  + (sum(Storage_In[i, l, t] * storage_eff_in[i, l] for l in LAYERS if  storage_eff_in[i,l] > 0) - sum(Storage_Out[i, l, t] / storage_eff_out[i,l] for l in LAYERS if storage_eff_out[i,l] > 0))*t_op[t])
    end

    for i=STORAGE_TECH,l=LAYERS,t=PERIODS
        @constraint(blk, Storage_In[i,l,t] * (ceil(storage_eff_in[i,l]) - 1) == 0.0)   # 1.15
        @constraint(blk, Storage_Out[i,l,t] * (ceil(storage_eff_out[i,l]) - 1) == 0.0) # 1.16
    end
    
    # 1.17 linealizado
    #@constraint(blk, storage_no_transfer_1[i=STORAGE_TECH,t=PERIODS],sum(Storage_In[i,l,t]*storage_eff_in[i,l] for l in LAYERS if storage_eff_in[i,l] > 0)*t_op[t]/f_max[i] <= Y_Sto_In[i,t])
    #@constraint(blk, storage_no_transfer_2[i=STORAGE_TECH,t=PERIODS],sum(Storage_Out[i,l,t]*storage_eff_out[i,l] for l in LAYERS if storage_eff_out[i,l] > 0)*t_op[t]/f_max[i] <= Y_Sto_Out[i,t])
    #@constraint(blk, storage_no_transfer_3[i=STORAGE_TECH,t=PERIODS],Y_Sto_In[i,t] + Y_Sto_Out[i,t] <= 1)

    # 1.18
    for i=END_USES_TYPES,t=PERIODS
       @constraint(blk, Losses[i,t] == sum(layers_in_out[j,i] * F_Mult_t[j,t] for j in setdiff(union(RESOURCES,TECHNOLOGIES),STORAGE_TECH) if layers_in_out[j, i] > 0) * loss_coeff[i])
    end

    # 1.19 Linealizado
    for i=setdiff(TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DECEN"],["DEC_SOLAR"]),t=PERIODS
        @constraint(blk, F_Mult_t[i,t] + X_Solar_Backup_Aux[i,t] >= sum(F_Mult_t[i,t2] * t_op[t2] for t2 in PERIODS) * ((M_end_uses_input["HEAT_LOW_T_HW"][s]/total_time + M_end_uses_input["HEAT_LOW_T_SH"][s]*heating_month[t]/t_op[t])/(M_end_uses_input["HEAT_LOW_T_HW"][s] + M_end_uses_input["HEAT_LOW_T_SH"][s])))
        @constraint(blk, X_Solar_Backup_Aux[i,t] <= f_max["DEC_SOLAR"] * Y_Solar_Backup[i])
        @constraint(blk, X_Solar_Backup_Aux[i,t] <= F_Mult_t["DEC_SOLAR",t])
        @constraint(blk, X_Solar_Backup_Aux[i,t] >= F_Mult_t["DEC_SOLAR",t] - (1 - Y_Solar_Backup[i]) * f_max["DEC_SOLAR"])
    end

    # 1.21                                                                                                                    
#   @constraint(blk, TotalGWP == sum(GWP_constr[i]/lifetime[i] for i in TECHNOLOGIES) + sum(GWP_op[j] for j in RESOURCES))

    # 1.22
    for i=END_USES_TYPES,j=TECHNOLOGIES_OF_END_USES_TYPE[i]
        @constraint(blk, sum(F_Mult_t[j, t] * t_op[t] for t in PERIODS) <= fmax_perc[j] * sum(F_Mult_t[j2,t2] * t_op[t2] for j2 in TECHNOLOGIES_OF_END_USES_TYPE[i], t2 in PERIODS)) 
        @constraint(blk, sum(F_Mult_t[j, t] * t_op[t] for t in PERIODS) >= fmin_perc[j] * sum(F_Mult_t[j2,t2] * t_op[t2] for j2 in TECHNOLOGIES_OF_END_USES_TYPE[i], t2 in PERIODS))
    end

    # 1.23
    for i=union(TECHNOLOGIES_OF_END_USES_CATEGORY["MOBILITY_PASSENGER"],TECHNOLOGIES_OF_END_USES_CATEGORY["MOBILITY_FREIGHT"]),t=PERIODS
        @constraint(blk, F_Mult_t[i,t] >= sum(F_Mult_t[i,t2] * t_op[t2] / total_time for  t2 in PERIODS))
    end

    # 1.25
    for t=PERIODS                                                                                                                                                      
        @constraint(blk, Storage_In["PUMPED_HYDRO","ELECTRICITY",t] <= (F_Mult_t["HYDRO_DAM",t] + F_Mult_t["NEW_HYDRO_DAM",t]))
    end
    
    # 1.27 linealizado
    for t=PERIODS
        @constraint(blk, Max_Heat_Demand_DHN >= End_Uses["HEAT_LOW_T_DHN",t] + Losses["HEAT_LOW_T_DHN",t])                                                                                                                
    end    

    @constraint(blk, sum(F_Mult[j] for j in TECHNOLOGIES_OF_END_USES_TYPE["HEAT_LOW_T_DHN"]) >= peak_dhn_factor * Max_Heat_Demand_DHN)


    # 1.31

    ### CONSTRAINTS  DEMAND ###

    for l=LAYERS, t=PERIODS
    @constraint(blk, End_Uses[l,t] ==  
	if l=="ELECTRICITY"
		M_end_uses_input[l][s] / total_time + M_end_uses_input["LIGHTING"][s] * lighting_month[t] / t_op[t] + Losses[l,t]
	elseif l=="HEAT_LOW_T_DHN"
		(M_end_uses_input["HEAT_LOW_T_HW"][s] / total_time + M_end_uses_input["HEAT_LOW_T_SH"][s] * heating_month[t] / t_op[t]) * Share_Heat_Dhn
	elseif l=="HEAT_LOW_T_DECEN"
		(M_end_uses_input["HEAT_LOW_T_HW"][s] / total_time + M_end_uses_input["HEAT_LOW_T_SH"][s] * heating_month[t] / t_op[t]) * (1 - Share_Heat_Dhn)
	elseif l=="MOB_PUBLIC"
		(M_end_uses_input["MOBILITY_PASSENGER"][s] / total_time) * Share_Mobility_Public
	elseif l=="MOB_PRIVATE"
		(M_end_uses_input["MOBILITY_PASSENGER"][s] / total_time) * (1 - Share_Mobility_Public)
	elseif l=="MOB_FREIGHT_RAIL"
 		(M_end_uses_input["MOBILITY_FREIGHT"][s] / total_time) * Share_Freight_Train
	elseif l=="MOB_FREIGHT_ROAD"
		(M_end_uses_input["MOBILITY_FREIGHT"][s] / total_time) * (1 - Share_Freight_Train)
	elseif l=="HEAT_HIGH_T"
		M_end_uses_input[l][s] / total_time
	else 0.0 end)
     end

end

