function r = rule(fcn)
%RULE Construct a custom session filter rule
%
%   r = rule(@(s) s.snr > 1 & s.nspikes > 10)

validateattributes(fcn, {'function_handle'}, {'scalar'});

r.type = 'rule';
r.fcn  = fcn;
end
