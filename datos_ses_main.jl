
i_rate = 0.03215; # I stage i_rate

datos = readdlm("end_uses_demand_year.txt",'\t');
n,m = size(datos);

end_uses_demand_year = Dict((datos[i,1],datos[1,j]) => datos[i,j] for i =2:n for j=2:m);

for i in END_USES_INPUT, j in SECTORS
    try
    end_uses_demand_year[i,j]
    catch error
       if isa(error, KeyError)
           end_uses_demand_year[i,j] = 0; # default value
       end
    end
end
            
share_mobility_public_min = 0.3;
share_mobility_public_max = 0.5;

share_freight_train_min = 0.4;
share_freight_train_max = 0.6;

share_heat_dhn_min = 0.1;
share_heat_dhn_max = 0.3;

datos = readdlm("PERIODS.txt",'\t');
n,m = size(datos);
t_op = Dict(datos[i,1] => datos[i,2] for i =2:n);
lighting_month = Dict(datos[i,1] => datos[i,3] for i =2:n);
heating_month = Dict(datos[i,1] => datos[i,4] for i =2:n);

datos = readdlm("layers_in_out.txt",'\t');
n,m = size(datos);
layers_in_out = Dict((datos[i,1],datos[1,j]) => datos[i,j] for i =2:n for j=2:m);

datos = readdlm("avail.txt",'\t');
n,m = size(datos);
avail = Dict(datos[i,1] => datos[i,2] for i =2:n);

datos = readdlm("gwp_op.txt",'\t');
n,m = size(datos);
gwp_op = Dict(datos[i,1] => datos[i,2] for i =2:n);

datos = readdlm("TECHNOLOGIES.txt",'\t');
n,m = size(datos);
ref_size = Dict(datos[i,1] => datos[i,2] for i =2:n);
c_inv = Dict(datos[i,1] => datos[i,3] for i =2:n);
c_maint = Dict(datos[i,1] => datos[i,4] for i =2:n);
gwp_constr = Dict(datos[i,1] => datos[i,5] for i =2:n);
lifetime = Dict(datos[i,1] => datos[i,6] for i =2:n); # I stage n
c_p = Dict(datos[i,1] => datos[i,7] for i =2:n);

for i in TECHNOLOGIES
    try
    c_p[i]
    catch error
       if isa(error, KeyError)
           c_p[i] = 1; # default value
       end
    end
end
                        
fmin_perc = Dict(datos[i,1] => datos[i,8] for i =2:n);
fmax_perc = Dict(datos[i,1] => datos[i,9] for i =2:n);

for i in TECHNOLOGIES
    try
    fmax_perc[i]
    catch error
       if isa(error, KeyError)
           fmax_perc[i] = 1; # default value
       end
    end
    try
    fmin_perc[i]
    catch error
       if isa(error, KeyError)
           fmin_perc[i] = 0; # default value
       end
    end
end

                        
f_min = Dict(datos[i,1] => datos[i,10] for i =2:n);
f_max = Dict(datos[i,1] => datos[i,11] for i =2:n);

datos = readdlm("c_p_t.txt",'\t');
n,m = size(datos);
c_p_t = Dict((datos[i,1],datos[1,j]) => datos[i,j] for i =2:n for j=2:m);

for i in TECHNOLOGIES, j in PERIODS
    try
    c_p_t[i,j]
    catch error
       if isa(error, KeyError)
           c_p_t[i,j] = 1.0; # default value
       end
    end
end
           
datos = readdlm("c_op.txt",'\t');
n,m = size(datos);
c_op = Dict((datos[i,1],datos[1,j]) => datos[i,j] for i =2:n for j=2:m);

datos = readdlm("storage_eff_in.txt",'\t');
n,m = size(datos);
storage_eff_in = Dict((datos[i,1],datos[1,j]) => datos[i,j] for i =2:n for j=2:m);
                                                            
datos = readdlm("storage_eff_out.txt",'\t');
n,m = size(datos);
storage_eff_out = Dict((datos[i,1],datos[1,j]) => datos[i,j] for i =2:n for j=2:m);
                                          
datos = readdlm("loss_coeff.txt",'\t');
n,m = size(datos);
loss_coeff = Dict(datos[i,1] => datos[i,2] for i =2:n);
                                                                        
for i in END_USES_TYPES
    try
    loss_coeff[i]
    catch error
       if isa(error, KeyError)
           loss_coeff[i] = 0; # default value
       end
    end
end
                                                                    
peak_dhn_factor = 2;
                                                                        
end_uses_input = Dict(i => sum([end_uses_demand_year[i,s] for s in SECTORS]) for i in END_USES_INPUT);
                                                                        
tau = Dict(i => i_rate*(1 + i_rate)^lifetime[i]/(((1 + i_rate)^lifetime[i])-1) for i in TECHNOLOGIES);
                                                                        
total_time = sum(t_op[t] for t in PERIODS);


