#-----------------------------------------------------------------------------80
#
#-----------------------------------------------------------------------------80
#' Compute number of swaps.
#'
#' This function computes the number of swaps.
#'
#' @param enco A vector.
#'
#' @import Rcpp
#'
compute_nswap_001 <- "int compute_nswap_001(NumericVector enco){
  int  swaps = 0;
  for(int i=0; i<(enco.length()-1); ++i){
    for(int j=i+1; j<enco.length(); ++j){
      if(enco[i] > enco[j])
        swaps++;
    }
  }
  return(swaps);
}"
cppFunction(compute_nswap_001)
#-----------------------------------------------------------------------------80
#
#-----------------------------------------------------------------------------80
#' Compute an edit distance between two vectors.
#'
#' This function computes the number of swaps of adjacent elements required for
#'   transforming vector 1 to vector 2, which have the same length and same
#'   amount of given numbers (e.g., vector1 = c(0,1,1), vector2 = c(1,1,0)).
#'   The following R code is inspired by Kendall tau distance algorithm.
#'
#' @param vec1 A first vector.
#' @param vec2 A second vector.
#
#' @return An integer representing an edit distance.
#' @import Rcpp
#'
compute_nswaps <- function(vec1, vec2){
  I <- length(vec1)

  # (1)
  dict <- c()
  for(w in unique(vec1)){
    val <- which(vec1 == w)
    dict <- c(dict, list(val))
  }
  names(dict) <- unique(vec1)

  # (2)
  cnt <- c()
  for(c in names(dict)){
    cnt <- c(cnt, list(1))
  }
  names(cnt) <- names(dict)
  enco <- vec2
  for(i in 1:I){
    enco[i] <- dict[[as.character(vec2[i])]][cnt[[as.character(vec2[i])]]]
    cnt[[as.character(vec2[i])]] <- cnt[[as.character(vec2[i])]] + 1
  }

  # (3): this step is time consuming.
  swaps <- compute_nswap_001(enco)

  return(swaps)
}
#-----------------------------------------------------------------------------80
#
#-----------------------------------------------------------------------------80
#' Compute separation indices of sign scores for given two clusters.
#'
#' This function computes separation indices of sign scores for given two
#'   clusters.
#'
#' @param sce A SingleCellExperiment object.
#' @param labels A vector of labels of all the samples.
#' @param ident_1 Label names identifying cluster numbers,
#'   e.g., ident_1 = 1, ident_1 = c(1, 3).
#' @param ident_2 Label names identifying cluster numbers,
#'   e.g., ident_2 = 2, ident_2 = c(2, 4).
#'
#' @return A SingleCellExperiment object.
#' @import SingleCellExperiment
#' @import SummarizedExperiment
#' @import S4Vectors
#' @export
#'
compute_sepI_clusters <- function(sce, labels, ident_1, ident_2){
  inds_1 <- which(labels %in% ident_1)
  inds_2 <- which(labels %in% ident_2)
  popu_1 <- colnames(sce)[inds_1]
  subsce <- sce[, sort(union(inds_1, inds_2))]
  submat <- as.matrix(assay(subsce, "counts"))
  res <- data.frame(
    Ident_1 = paste(ident_1, collapse = "/"),
    Ident_2 = paste(ident_2, collapse = "/"),
    SignID = NA,
    Description = NA,
    CorrGene = NA,
    WeakCorrGene = NA,
    sepI = NA,
    Rank = rep(NA, dim(subsce)[1])
  )
  for(i in 1:dim(subsce)[1]){
    res$SignID[i] <- rownames(subsce)[i]
    res$Description[i] <- rowData(subsce)$Description[i]
    res$CorrGene[i] <- rowData(subsce)$CorrGene[i]
    res$WeakCorrGene[i] <- rowData(subsce)$WeakCorrGene[i]
    #--------------------------------------------------
    # Compute edit distances between (0, 1)-vectors
    #--------------------------------------------------
    data <- submat[which(rownames(submat) == res$SignID[i]), ]
    vec_1 <- sort(data, decreasing = FALSE)
    vec_1 <- ifelse(names(vec_1) %in% popu_1, 1, 0)
    vec_2 <- sort(vec_1, decreasing = FALSE) # vec_2 = (0, 0, ..., 1, 1)
    vec_3 <- sort(vec_1, decreasing = TRUE)  # vec_3 = (1, 1, ..., 0, 0)
    dist1 <- compute_nswaps(vec_1, vec_2)
    dist2 <- compute_nswaps(vec_1, vec_3)
    res$sepI[i] <- round(1 - 2 * dist1 / (dist1 + dist2), digits = 6)
  }
  #--------------------------------------------------
  # Arrange the data frame in order of res$sepI
  #--------------------------------------------------
  inds <- order(res$sepI, decreasing = TRUE)
  res <- res[inds, ]
  res$Rank <- 1:length(inds)
  rownames(res) <- 1:nrow(res)
  #--------------------------------------------------
  # Output
  #--------------------------------------------------
  slot_name <- paste("Label_", paste(ident_1, collapse = "/"), "_vs_",
                     paste(ident_2, collapse = "/"), sep = "")
  metadata(sce)$marker_signs[[slot_name]] <- res

  return(sce)
}
#-----------------------------------------------------------------------------80
#
#-----------------------------------------------------------------------------80
#' Compute separation indices for each cluster against the others.
#'
#' This function computes separation indices for each cluster versus the others.
#'
#' @param sce A SingleCellExperiment object.
#' @param labels A vector of labels of all the samples (cells).
#'
#' @return A SingleCellExperiment object.
#' @import SingleCellExperiment
#' @import SummarizedExperiment
#' @import S4Vectors
#' @export
#'
compute_sepI_all <- function(sce, labels){
  #--------------------------------------------------
  # Preparation
  #--------------------------------------------------
  res <- list()
  tmp <- sce
  metadata(tmp)$marker_signs <- NULL
  #--------------------------------------------------
  # Loop
  #--------------------------------------------------
  idents <- unique(sort(labels))
  for(i in 1:length(idents)){
    ident_1 <- idents[i]
    ident_2 <- setdiff(idents, ident_1)
    tmp <- compute_sepI_clusters(sce = tmp, labels = labels,
                                 ident_1 = ident_1, ident_2 = ident_2)
    res[[i]] <- metadata(tmp)$marker_signs[[i]]
    slot_name <- paste("Label_", paste(ident_1, collapse = "/"), "_vs_",
                       paste(ident_2, collapse = "/"), sep = "")
    metadata(sce)$marker_signs[[slot_name]] <- res[[i]]
  }
  res_all <- c()
  for(i in 1:length(res)){
    res_all <- rbind(res_all, res[[i]])
  }
  rownames(res_all) <- 1:nrow(res_all)
  metadata(sce)$marker_signs$all <- res_all

  return(sce)
}
