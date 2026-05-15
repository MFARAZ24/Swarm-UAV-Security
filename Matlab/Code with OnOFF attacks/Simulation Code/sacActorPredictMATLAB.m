function delta_T = sacActorPredictMATLAB(obs, actorFile)
% Runs exported SAC actor network in MATLAB.

    persistent actor cachedFile

    if isempty(actor) || isempty(cachedFile) || ~strcmp(cachedFile, actorFile)
        actor = load(actorFile);
        cachedFile = actorFile;
    end

    x = double(obs(:)');

    obs_mean = double(actor.obs_mean(:)');
    obs_var = double(actor.obs_var(:)');
    obs_epsilon = double(actor.obs_epsilon(1));
    clip_obs = double(actor.clip_obs(1));

    x = (x - obs_mean) ./ sqrt(obs_var + obs_epsilon);
    x = max(min(x, clip_obs), -clip_obs);

    x = x(:);

    W1 = double(actor.latent_pi_0_weight);
    b1 = double(actor.latent_pi_0_bias(:));

    W2 = double(actor.latent_pi_2_weight);
    b2 = double(actor.latent_pi_2_bias(:));

    Wmu = double(actor.mu_weight);
    bmu = double(actor.mu_bias(:));

    z1 = W1 * x + b1;
    z1 = max(z1, 0);

    z2 = W2 * z1 + b2;
    z2 = max(z2, 0);

    mu = Wmu * z2 + bmu;

    action_squashed = tanh(mu);

    action_scale = double(actor.action_scale(1));
    action_bias = double(actor.action_bias(1));

    delta_T = action_bias + action_scale * action_squashed;
    delta_T = double(delta_T(1));
end