#!/usr/bin/Rscript
### SIAMCAT - Statistical Inference of Associations between
### Microbial Communities And host phenoTypes R flavor EMBL
### Heidelberg 2012-2018 GNU GPL 3.0

#' @title Make predictions on a test set
#'
#' @description This function takes a \link{siamcat-class}-object containing
#'     a model trained by \link{train.model} and performs predictions on
#'     a given test-set.
#'
#' @usage make.predictions(siamcat, siamcat.holdout = NULL,
#'     normalize.holdout = TRUE, verbose = 1)
#'
#' @param siamcat object of class \link{siamcat-class}
#'
#' @param siamcat.holdout optional, object of class \link{siamcat-class} on
#'     which to make predictions, defaults to \code{NULL}
#'
#' @param normalize.holdout boolean, should the holdout features be normalized
#'     with a frozen normalization (see \link{normalize.features}) using the
#'     normalization parameters in \code{siamcat}?, defaults to \code{TRUE}
#'
#' @param verbose integer, control output: \code{0} for no output at all,
#'     \code{1} for only information about progress and success, \code{2} for
#'     normal level of information and \code{3} for full debug information,
#'     defaults to \code{1}
#'
#' @export
#'
#' @keywords SIAMCAT make.predictions
#'
#' @return object of class \link{siamcat-class} with the slot \code{pred_matrix}
#'     filled
#'
#' @details This functions uses the model in the \code{model_list}-slot of the
#'     \code{siamcat} object to make predictions on a given test set. The
#'     test set can either consist of the test instances in the cross-
#'     validation, saved in the \code{data_split}-slot of the same
#'     \code{siamcat} object, or a completely external feature set, given in
#'     the form of another \code{siamcat} object (\code{siamcat.holdout}).
#'
#' @examples
#' data(siamcat_example)
#'
#' # Simple example
#' siamcat.pred <- make.predictions(siamcat_example)
#'
#' # Predictions on a holdout-set
#' \donttest{pred.mat <- make.predictions(siamcat.trained, siamcat.holdout,
#'     normalize.holdout=TRUE)}
make.predictions <- function(siamcat,
    siamcat.holdout = NULL,
    normalize.holdout = TRUE,
    verbose = 1) {
    s.time <- proc.time()[3]

    # if holdout is NULL, make predictions on data in siamcat
    if (is.null(siamcat.holdout)) {
        if (verbose > 1)
            message("+ starting make.predictions on siamcat object")

        # label
        label <- label(siamcat)
        if (label$type == 'TEST'){
            stop('SIAMCAT can not predict on a reference object with a',
                ' TEST label. Exiting...')
        }
        # data.split
        if (is.null(data_split(siamcat, verbose=0))){
            stop('SIAMCAT needs a data split for predictions! Exiting...')
        }
        data.split <- data_split(siamcat)
        # models
        if (is.null(models(siamcat, verbose=0))){
            stop('SIAMCAT does not seem to contain any models. Exiting...')
        }
        models <- models(siamcat)
        # features
        feature.type <- feature_type(siamcat)
        if (feature.type == 'original'){
            feat <- get.orig_feat.matrix(siamcat)
        } else if (feature.type == 'filtered'){
            feat <- get.filt_feat.matrix(siamcat)
        } else if (feature.type == 'normalized'){
            feat <- get.norm_feat.matrix(siamcat)
        }
        rownames(feat) <- make.names(rownames(feat))
        feat <- t(feat)

        label.fac <-
            factor(label$label,
                levels = sort(label$info))

        num.folds <- data.split$num.folds
        num.resample <- data.split$num.resample

        pred <- matrix(NA, ncol = num.resample, nrow = length(label.fac),
                dimnames = list(names(label.fac), paste0("CV_rep",
                    seq_len(num.resample))))
        i = 1
        if (verbose == 1 || verbose == 2)
            pb <- progress_bar$new(total = num.folds * num.resample)
        for (f in seq_len(num.folds)) {
            for (r in seq_len(num.resample)) {
                test.label <- label.fac[data.split$test.folds[[r]][[f]]]
                data <-
                    as.data.frame(feat[data.split$test.folds[[r]][[f]], ,drop=FALSE])

                # assert stuff
                stopifnot(nrow(data) == length(test.label))
                stopifnot(all(rownames(data) == names(test.label)))

                model <- models[[i]]

                stopifnot(!any(rownames(model$task$env$data) %in%
                    rownames(data)))

                # subselect features for each model
                # needs to be added due to feature selection
                data <- data[,model$features]

                data$label <- test.label

                if (verbose > 2)
                    message(paste0("Applying ", model_type(siamcat),
                        " on cv_fold", f, "_rep", r, " (", i, " of ",
                        num.resample * num.folds, ")..."))

                task <-
                    makeClassifTask(data = data, target = "label",
                                    fixup.data='quiet', check.data=FALSE)
                pdata <- predict(model, task = task)

                p <- pdata$data[, 4]
                names(p) <- rownames(pdata$data)
                pred[names(p), r] <- p
                i <- i + 1
                if (verbose == 1 || verbose == 2)
                    pb$tick()
            }
        }
        stopifnot(!any(is.na(pred)))
        pred_matrix(siamcat) <- pred
        r.object <- siamcat
    } else {
        if (verbose > 1)
            message("+ starting make.predictions on external dataset")

        # check reference set
        if (is.null(data_split(siamcat, verbose=0))){
            stop('Reference SIAMCAT object should contain a data split.',
                ' Exiting...')
        }
        data.split <- data_split(siamcat)
        if (is.null(models(siamcat, verbose=0))){
            stop('Reference SIAMCAT object should contains models. Exiting...')
        }
        models <- models(siamcat)

        feature.type <- feature_type(siamcat)

        if (feature.type == 'normalized'){

            if (normalize.holdout) {
                if (verbose > 1)
                    message("+ Performing frozen normalization on holdout set")
                siamcat.holdout <- normalize.features(siamcat.holdout,
                    norm.param = norm_params(siamcat), feature.type='original',
                    verbose = verbose)
                } else {
                    warning("WARNING: holdout set is not being normalized!")
                    if (is.null(norm_feat(siamcat.holdout, verbose=0))){
                        stop('Holdout set has not been normalized yet!')
                    }
                }
            feat.test <- get.norm_feat.matrix(siamcat.holdout)
        } else if (feature.type == 'filtered') {
            if (is.null(filt_feat(siamcat.holdout, verbose=0))){
                stop('Holdout set has not been filtered yet!')
            }
            feat.test <- get.filt_feat.matrix(siamcat.holdout)
        } else if (feature.type == 'original'){
            feat.test <- get.orig_feat.matrix(siamcat.holdout)
        }
        rownames(feat.test) <- make.names(rownames(feat.test))
        feat.test <- t(feat.test)

        if (feature.type == 'normalized'){
            feat.ref <- get.norm_feat.matrix(siamcat)
        } else if (feature.type == 'filtered') {
            feat.ref <- get.filt_feat.matrix(siamcat)
        } else if (feature.type == 'original'){
            feat.ref <- get.orig_feat.matrix(siamcat)
        }
        rownames(feat.ref) <- make.names(rownames(feat.ref))
        feat.ref <- t(feat.ref)

        label <- label(siamcat.holdout)

        # data sanity checks
        stopifnot(all(colnames(feat.ref) %in% colnames(feat.test)))

        # prediction
        num.models <- data.split$num.folds * data.split$num.resample

        pred <- matrix(NA, ncol = num.models, nrow = nrow(feat.test),
                dimnames = list(rownames(feat.test), paste0("Model_",
                    seq_len(num.models))))
        if (verbose == 1 || verbose == 2)
            pb <- progress_bar$new(
                total = data.split$num.folds*data.split$num.resample)
        for (i in seq_len(num.models)) {
            data <- as.data.frame(feat.test)
            model <- models[[i]]

            data <- data[, model$features]
            data$label <- factor(label$label, levels=c(label$info))

            if (verbose > 2)
                message(paste0("Applying ", model_type(siamcat),
                    " on complete external dataset", " (", i, " of ",
                    num.models, ")..."))

            task <- makeClassifTask(data = data, target = "label",
                                    fixup.data='quiet', check.data=FALSE)
            pdata <- predict(model, task = task)

            p <- pdata$data[, 4]
            names(p) <- rownames(pdata$data)
            pred[names(p), i] <- p

            if (verbose == 1 || verbose == 2)
                pb$tick()
        }
        pred_matrix(siamcat.holdout) <- pred
        r.object <- siamcat.holdout
    }

    # print correlation matrix
    if (verbose > 1)
        message(paste("Total number of predictions made:", length(pred)))
    correlation <- cor(pred, method = "spearman")
    if (verbose > 1)
        message("Correlation between predictions from repeated CV:")
    if (verbose > 1)
        message(paste("\tMin: ", min(correlation), "\n\tMedian: ",
            median(correlation), "\n\tMean: ", mean(correlation)))

    # print out time
    e.time <- proc.time()[3]
    if (verbose > 1)
        message(paste(
            "+ finished make.predictions in",
            formatC(e.time - s.time, digits = 3),
            "s"
        ))
    if (verbose == 1)
        message("Made predictions successfully.")

    return(r.object)
}
