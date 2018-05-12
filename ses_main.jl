
## MAIN SETS
include("Conjuntos_ses_main.jl")

## PARAMETERS
include("datos_ses_main.jl")

## leer modelo
include("modelo_ses_main_stochastic_ver3.jl");

solve_types = [:Dual, :Benders, :Extensive];

# Default parameter file
myparam = "default.txt";

status = solve(modelo, solve_type = solve_types[3], param = myparam)

@show getobjectivevalue(modelo)


#LinearConstraint(storage_level[1,1])

#println(getdual(totalGWP_calc))

#f = open("model.lp", "w")
#print(f, modelo)
#close(f)

#f = open("solucion.txt", "w")
#for i in TECHNOLOGIES
#    println(f,"let Number_Of_Units['$(i)'] := $(getvalue(Number_Of_Units[i]));")
#    println(f,"let F_Mult['$(i)'] := $(getvalue(F_Mult[i]));")
#    println(f,"let C_inv['$(i)'] := $(getvalue(C_inv[i]));")
#    println(f,"let C_maint['$(i)'] := $(getvalue(C_maint[i]));")
#    println(f,"let Y_Solar_Backup['$(i)'] := $(getvalue(Y_Solar_Backup[i]));")
#    println(f,"let GWP_constr['$(i)'] := $(getvalue(GWP_constr[i]));")
#end

#for i in LAYERS, t in PERIODS
#    println(f,"let End_Uses['$(i)',$(t)] := $(getvalue(End_Uses[i,t]));")
#end

#for i in union(RESOURCES,TECHNOLOGIES), t in PERIODS
#    println(f,"let F_Mult_t['$(i)',$(t)] := $(getvalue(F_Mult_t[i,t]));")
#end

#for i in RESOURCES
#    println(f,"let C_op['$(i)'] := $(getvalue(C_op[i]));")
#end

#for in i STORAGE_TECH, j in LAYERS, t in PERIODS
#    println(f,"Storage_In['$(i)','$(j)',$(t)] := $(getvalue(Storage_In[i,j,t]));")

#close(f)

#MathProgBase.numvar(modelo) # devuelve el numero de variables
#MathProgBase.numlinconstr(modelo) # devuelve el numero de restricciones lineales

#numbers = rand(5000,5000);
#writedlm("test.txt", numbers)
#numbers = readdlm("test.txt");


