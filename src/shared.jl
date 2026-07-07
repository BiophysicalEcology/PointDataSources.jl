"""
    _nearest_index(coord, target) -> Int
    _nearest_index(coord, target, tol) -> Int

Index into a 1-D coordinate vector closest to `target`. The 3-arg form
throws `ArgumentError` if the nearest coordinate is farther than `tol` away
(catches "point outside the grid" instead of silently returning an edge
cell). Replaces the several inconsistent per-source nearest-cell lookups
in the R prior art (NicheMapR) with one tested utility.
"""
function _nearest_index(coord::AbstractVector{<:Real}, target::Real)
    isempty(coord) && throw(ArgumentError("coordinate vector is empty"))
    return argmin(abs.(coord .- target))
end

function _nearest_index(coord::AbstractVector{<:Real}, target::Real, tol::Real)
    i = _nearest_index(coord, target)
    Δ = abs(coord[i] - target)
    Δ > tol && throw(ArgumentError(
        "nearest grid coordinate ($(coord[i])) is $(Δ) from requested $target, " *
        "exceeding tolerance $tol -- point is likely outside this grid's domain"
    ))
    return i
end

# Small relative buffer avoids rejecting points that sit right at the cell
# edge due to floating-point rounding noise, not real out-of-bounds points.
_half_cell(coord::AbstractVector) = abs(coord[2] - coord[1]) / 2 * 1.001

"""
    _normalize_lon(coord, lon) -> Real

Adjust `lon` to whichever longitude convention `coord` itself uses (0–360°E
vs -180..180), inferred from `coord`'s own range, so callers can always
pass `lon` in the familiar -180..180 convention regardless of a given
source's native grid (e.g. NCEP publishes 0–360°E; GRIDMET/BARRA use
-180..180).
"""
function _normalize_lon(coord::AbstractVector{<:Real}, lon::Real)
    if maximum(coord) > 180 && lon < 0
        return lon + 360
    elseif maximum(coord) <= 180 && lon > 180
        return lon - 360
    end
    return lon
end

"""
    _retry(f; attempts=3, sleep=2)

Call `f()`, retrying on any exception up to `attempts` times with a `sleep`
second pause between attempts, then rethrowing the last error.
"""
function _retry(f; attempts=3, sleep=2)
    for i in 1:attempts
        try
            return f()
        catch e
            i == attempts && rethrow()
            @warn "retry $i/$attempts after error" exception = e
            sleep > 0 && Base.sleep(sleep)
        end
    end
end

_end_of_day(d::Date) = DateTime(d) + Day(1) - Millisecond(1)
_end_of_day(dt::DateTime) = dt

# A bare `Date` end-bound means "through the end of that day" for sub-daily
# sources (NCEP, BARRA), not "through midnight" -- otherwise most of the
# last day's readings would be silently excluded.
_point_daterange(date::Dates.TimeType) = (date, _end_of_day(date))
_point_daterange(dates::Tuple{<:Any,<:Any}) = (first(dates), _end_of_day(last(dates)))
_point_daterange(dates::AbstractVector) = (first(dates), _end_of_day(last(dates)))

_period_start(::Type{Month}, d::Date) = Date(year(d), month(d), 1)
_period_start(::Type{Year}, d::Date) = Date(year(d), 1, 1)

"""
    _periods_spanned(step, start, finish) -> StepRange{Date}

One representative date per period-chunked remote file (a calendar month
for `step=Month(1)`, a calendar year for `step=Year(1)`) touched by
`start..finish`. Anchors both ends to the first day of their period before
stepping, so e.g. a range starting on the 30th of a month doesn't overshoot
past a shorter following month (`Date(2020,1,30) + Month(1) == Date(2020,2,28)`,
which would otherwise skip February entirely).
"""
function _periods_spanned(step::Union{Month,Year}, start::Date, finish::Date)
    T = step isa Month ? Month : Year
    _period_start(T, start):step:_period_start(T, finish)
end

"""
    _concat_over_files(dates_seq, open_and_slice)

For sources chunked into one file per period (NCEP: yearly, BARRA:
monthly), a requested date range can span multiple files. `dates_seq` is
one representative date per file (e.g. from `RasterDataSources.date_sequence`);
`open_and_slice(d) -> (times, values, units)` opens the file for `d` and
returns whatever portion of the requested range it contains (empty vectors
if none). Results are concatenated in order.
"""
function _concat_over_files(dates_seq, open_and_slice)
    times, values, units = DateTime[], Float64[], ""
    for d in dates_seq
        t, v, u = open_and_slice(d)
        append!(times, t)
        append!(values, v)
        isempty(u) || (units = u)
    end
    return times, values, units
end
