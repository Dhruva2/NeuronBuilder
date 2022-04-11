### Basic components and subtypes
abstract type Species end
abstract type Ion <: Species end
abstract type AbstractIon <: Ion end

"""
Not including voltage in tagging ion channels. Any flow channel. Flows are all charged particles. So they will always include voltage. Not going to consider flows of e.g. proteins
"""
struct Voltage <: Species end
struct Sodium <: Ion end
struct Potassium <: Ion end
struct Calcium <: Ion end
struct Proton <: Ion end
struct Leak <: AbstractIon end
abstract type Reversal{Ion} end

ionic(x) = x <: Ion
export ionic

shorthand_name(::Type{Voltage}) = :V
shorthand_name(::Type{Sodium}) = :Na
shorthand_name(::Type{Potassium}) = :K
shorthand_name(::Type{Calcium}) = :Ca
shorthand_name(::Type{Proton}) = :H
shorthand_name(::Type{Leak}) = :Leak
shorthand_name(::Type{Reversal{T}}) where {T} = Symbol(:E, shorthand_name(T))
export shorthand_name




abstract type Component end
abstract type Compartment <: Component end
abstract type FlowChannel{Sensors,Actuators} <: Component end

struct ComponentSystem{C<:Component,S<:AbstractTimeDependentSystem}
    c::C
    sys::S
end

# is_geometric(::Compartment{T}) = T
# is_geometric(::Component) = false

### channels always sense the reversal of the currents they actuate

FlowChannel(T) = FlowChannel{Reversal{T},T}
FlowChannel(S, A) = FlowChannel{Tuple{S,Reversal{A}},A}

sensed(::FlowChannel{S,A}) where {S<:Tuple,A} = fieldtypes(S)
actuated(::FlowChannel{S,A}) where {S,A<:Tuple} = fieldtypes(A)

sensed(::FlowChannel{S,A}) where {S,A} = (S,)
actuated(::FlowChannel{S,A}) where {S,A} = (A,)

export sensed, actuated

flows(i::FlowChannel) = (sensed(i)..., actuated(i)...) |> unique
ions(i::FlowChannel) = filter(x -> x <: Ion, flows(i)) |> unique

struct TestChannel1 <: FlowChannel{Sodium,Potassium} end
struct TestChannel2 <: FlowChannel{Tuple{Sodium,Calcium},Potassium} end
struct TestChannel3 <: FlowChannel{Tuple{Sodium,Calcium},Tuple{Potassium,Proton}} end
struct TestChannel4 <: FlowChannel{Tuple{Voltage,Sodium},Tuple{Voltage,Potassium}} end
export TestChannel1, TestChannel2, TestChannel3, TestChannel4

sensedvars(i::FlowChannel) =
    map(sensed(i)) do thing
        Symbol(thing |> shorthand_name)
    end


reversals(i::FlowChannel) =
    map(actuated(i)) do thing
        Symbol(:E, shorthand_name(thing))
    end

currents(i::FlowChannel) =
    map(actuated(i)) do thing
        Symbol(:I, shorthand_name(thing))
    end

conductances(i::FlowChannel) =
    map(actuated(i)) do thing
        Symbol(:g, shorthand_name(thing))
    end


instantiate_variables(c::Component, args...) =
    map(args) do el
        map(el(c)) do f
            @variables $f(t)
        end |> Iterators.flatten |> collect
    end |> Iterators.flatten |> collect

instantiate_parameters(c::Component, args...) =
    map(args) do el
        map(el(c)) do f
            @parameters $f
        end |> Iterators.flatten |> collect
    end |> Iterators.flatten |> collect


instantiate_variables(v::Vector{Symbol}) =
    map(v) do f
        @variables $f(t)
    end |> Iterators.flatten |> collect

get_actuator(c::ComponentSystem{C,S}, v::Type{Voltage}) where {C<:FlowChannel,S} =
    sum(currents(c.c)) do I
        ModelingToolkit.getvar(c.sys, I; namespace=true)
    end

function get_actuator(c::ComponentSystem{C,S}, f::DataType) where {C<:FlowChannel,S}
    indx = findfirst(x -> x == f, actuated(c.c))
    isnothing(indx) && return Num(0.0)
    return ModelingToolkit.getvar(c.sys, currents(c.c)[indx]; namespace=true)
end

function get_sensor(c::ComponentSystem{C,S}, f::DataType) where {C<:FlowChannel,S}
    if f ∈ sensed(c.c)
        return ModelingToolkit.getvar(c.sys, shorthand_name(f); namespace=true)
    end
end
get_sensor(c::ComponentSystem{C,S}, f::Type{Voltage}) where {C<:FlowChannel,S} =
    ModelingToolkit.getvar(c.sys, shorthand_name(f); namespace=true)




export reversals, currents, flows, conductances, instantiate_variables, instantiate_parameters, sensedvars, current, get_sensor, get_actuator


abstract type Synapse <: Component end
struct EmptyConnection <: Synapse end

### delete these asap
abstract type IonChannel <: Component end
abstract type CalciumChannel <: IonChannel end
### 



abstract type RegIonChannel <: Component end # delete eventually
abstract type PlasticityRule <: Component end

struct Soma{F<:AbstractFloat} <: Compartment
    initial_states::Dict{Symbol,F}
    parameters::Dict{Symbol,F}
end





# flows(c::ComponentSystem) = flows(c.c)
# sensedvars(c::ComponentSystem) = sensedvars(c.c)
# reversals(c::ComponentSystem) = reversals(c.c)
# currents(c::ComponentSystem) = currents(c.c)
# conductances(c::ComponentSystem) = conductances(c.c)

# export getva


"""
delete when PlasticityRule overrides
"""
struct RegIon{F<:AbstractFloat,I<:IonChannel} <: RegIonChannel
    ionch::I
    Rion::F
    τion::Symbol
end



"""
    Prinz_conversion(s::Soma)
This function converts bare parameters in units of milliSiemens/cm2 (as used by the prinz paper) to conform with units of microSiemens/mm2

"""
Prinz_conversion(s::Soma) = s.parameters[:Cₘ] / s.parameters[:area]

"""
    Liu_conversion(s::Soma)
This function converts bare parameters in units of microSiemens/nanoFarads (as used by the Liu paper) to conform with units of microSiemens/mm2

"""
Liu_conversion(s::Soma) = s.parameters[:Cₘ]

"""
    syn_conv_factor(s::Soma)
This function converts bare synaptic parameters in units of nanoSiemens*area (as used by the prinz paper, where area is baked in the synaptic conductances) to conform with units of microSiemens/mm2

"""
syn_conv_factor(s::Soma) = 1e-3 / s.parameters[:area]^2 #this gives μS/mm^2 



######### Geometries ##############
"""
Every geometry needs methods for:
    capacitance()
    maybe reversals as dictionary?
    initial_conditions(f::Species)
"""

abstract type Geometry end
struct NoGeometry{C} <: Geometry
    capacitance::C
end
capacitance(g::NoGeometry) = g.capacitance

abstract type Neuron <: Compartment end

#### Dynamics #######
"""
Each flow dynamics struct needs a functor: 
    (s::SomeDynamics)(n::Neuron, variable, currents)

In the very near future need to add inputs and synaptic currents to this way of building
"""


abstract type SpeciesDynamics{F} end
struct BasicVoltageDynamics <: SpeciesDynamics{Voltage} end
"""
currents should include synaptic current
"""
function (b::BasicVoltageDynamics)(n::Neuron, vars, varnames, flux)
    C = capacitance(n.geometry)
    V = vars[findfirst(x -> x == Voltage, varnames)]
    return D(V) ~ (1 / C) * (flux)
end


struct LiuCalciumDynamics{T<:Number} <: SpeciesDynamics{Calcium}
    τCa::T
    Ca∞::T
    calc_multiplier::T # f * area = 14.96 * 0.0628
end

function (l::LiuCalciumDynamics)(n::Neuron, vars, varnames, currents)
    Ca = vars[findfirst(x -> x == Calcium, varnames)]
    C = capacitance(n.geometry)
    D(Ca) ~ (1 / l.τCa) * (-Ca + l.Ca∞ + (l.calc_multiplier * currents / C))
end


struct LiuCaReversalDynamics <: SpeciesDynamics{Calcium} end

function (l::LiuCaReversalDynamics)(n::Neuron, vars, varnames, currents)
    Ca = vars[findfirst(x -> x == Calcium, varnames)]
    ECa = vars[findfirst(x -> x == Reversal{Calcium}, varnames)]
    return ECa ~ (500.0) * (8.6174e-5) * (283.15) * (log(max((3000.0 / Ca), 0.001)))
end



