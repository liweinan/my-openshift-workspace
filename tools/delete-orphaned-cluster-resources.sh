#!/bin/bash

# Delete orphaned cluster resources by cluster name
# This script deletes Route53 records and other resources for clusters without infraID

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to find Route53 records
find_route53_records() {
    local cluster_name="$1"
    local aws_region="$2"
    local hosted_zone_id="Z3B3KOVA3TRCWP"  # qe.devcluster.openshift.com.
    
    aws --region "${aws_region}" route53 list-resource-record-sets \
        --hosted-zone-id "${hosted_zone_id}" \
        --query "ResourceRecordSets[?contains(Name, \`${cluster_name}\`)]" \
        --output json 2>/dev/null || echo "[]"
}

# Function to find CloudFormation stacks
find_cloudformation_stacks() {
    local cluster_name="$1"
    local aws_region="$2"
    
    aws --region "${aws_region}" cloudformation list-stacks \
        --query "StackSummaries[?contains(StackName, \`${cluster_name}\`) && StackStatus != 'DELETE_COMPLETE' && StackStatus != 'DELETE_IN_PROGRESS'].[StackName,StackStatus]" \
        --output text 2>/dev/null || echo ""
}

# Function to find S3 buckets
find_s3_buckets() {
    local cluster_name="$1"
    local aws_region="$2"
    
    aws --region "${aws_region}" s3api list-buckets \
        --query "Buckets[?contains(Name, \`${cluster_name}\`)].Name" \
        --output text 2>/dev/null || echo ""
}

# Function to find EC2 instances
find_ec2_instances() {
    local cluster_name="$1"
    local aws_region="$2"
    
    aws --region "${aws_region}" ec2 describe-instances \
        --query "Reservations[].Instances[?Tags[?contains(Value, \`${cluster_name}\`)]].InstanceId" \
        --output text 2>/dev/null || echo ""
}

# Function to find EC2 volumes
find_ec2_volumes() {
    local cluster_name="$1"
    local aws_region="$2"
    
    aws --region "${aws_region}" ec2 describe-volumes \
        --query "Volumes[?Tags[?contains(Value, \`${cluster_name}\`)]].VolumeId" \
        --output text 2>/dev/null || echo ""
}

# Function to find Load Balancers
find_load_balancers() {
    local cluster_name="$1"
    local aws_region="$2"
    
    aws --region "${aws_region}" elbv2 describe-load-balancers \
        --query "LoadBalancers[?contains(LoadBalancerName, \`${cluster_name}\`)].LoadBalancerArn" \
        --output text 2>/dev/null || echo ""
}

# Function to delete Route53 records
delete_route53_records() {
    local cluster_name="$1"
    local aws_region="$2"
    local dry_run="$3"
    
    print_info "Processing Route53 records for cluster: ${cluster_name}"
    
    local records=$(find_route53_records "${cluster_name}" "${aws_region}")
    
    if [ "${records}" = "[]" ] || [ -z "${records}" ]; then
        print_info "No Route53 records found for cluster: ${cluster_name}"
        return 0
    fi
    
    if [ "${dry_run}" = true ]; then
        print_warning "Found Route53 records for cluster ${cluster_name}:"
        echo "${records}" | jq -r '.[] | "  - \(.Name) (\(.Type))"'
        return 0
    fi
    
    print_warning "Found Route53 records for cluster ${cluster_name}:"
    echo "${records}" | jq -r '.[] | "- \(.Name) (\(.Type))"'
    echo ""
    
    print_info "Deleting Route53 records..."
    local hosted_zone_id="Z3B3KOVA3TRCWP"  # qe.devcluster.openshift.com.
    
    # Delete each record individually to avoid batch issues
    echo "${records}" | jq -r '.[] | @base64' | while read -r record_b64; do
        if [ -n "${record_b64}" ]; then
            local record=$(echo "${record_b64}" | base64 -d)
            local record_name=$(echo "${record}" | jq -r '.Name')
            local record_type=$(echo "${record}" | jq -r '.Type')
            
            print_info "Deleting Route53 record: ${record_name} (${record_type})"
            
            # Create change batch for this single record
            local change_batch=$(echo "${record}" | jq -c '{
                Changes: [{
                    Action: "DELETE",
                    ResourceRecordSet: .
                }]
            }')
            
            local change_id=$(aws --region "${aws_region}" route53 change-resource-record-sets \
                --hosted-zone-id "${hosted_zone_id}" \
                --change-batch "${change_batch}" \
                --query 'ChangeInfo.Id' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "${change_id}" ]; then
                print_success "Deleted Route53 record: ${record_name} (Change ID: ${change_id})"
            else
                print_error "Failed to delete Route53 record: ${record_name}"
            fi
        fi
    done
    
    print_info "Route53 records deletion process completed"
    print_info "Deletion may take a few minutes to propagate"
}

# Function to delete CloudFormation stacks
delete_cloudformation_stacks() {
    local cluster_name="$1"
    local aws_region="$2"
    local dry_run="$3"
    
    print_info "Processing CloudFormation stacks containing: ${cluster_name}"
    
    local stacks=$(find_cloudformation_stacks "${cluster_name}" "${aws_region}")
    
    if [ -z "${stacks}" ]; then
        print_info "No CloudFormation stacks found containing: ${cluster_name}"
        return 0
    fi
    
    if [ "${dry_run}" = true ]; then
        print_warning "Found CloudFormation stacks:"
        echo "${stacks}" | while read -r stack_name stack_status; do
            if [ -n "${stack_name}" ]; then
                echo "  - ${stack_name}: ${stack_status}"
            fi
        done
        return 0
    fi
    
    print_warning "Found CloudFormation stacks:"
    echo "${stacks}" | while read -r stack_name stack_status; do
        if [ -n "${stack_name}" ]; then
            echo "  - ${stack_name}: ${stack_status}"
        fi
    done
    echo ""
    
    echo "${stacks}" | while read -r stack_name stack_status; do
        if [ -n "${stack_name}" ]; then
            print_info "Deleting CloudFormation stack: ${stack_name}"
            aws --region "${aws_region}" cloudformation delete-stack --stack-name "${stack_name}" 2>/dev/null || print_warning "Failed to delete stack: ${stack_name}"
        fi
    done
}

# Function to delete S3 buckets
delete_s3_buckets() {
    local cluster_name="$1"
    local aws_region="$2"
    local dry_run="$3"
    
    print_info "Processing S3 buckets containing: ${cluster_name}"
    
    local buckets=$(find_s3_buckets "${cluster_name}" "${aws_region}")
    
    if [ -z "${buckets}" ]; then
        print_info "No S3 buckets found containing: ${cluster_name}"
        return 0
    fi
    
    if [ "${dry_run}" = true ]; then
        print_warning "Found S3 buckets:"
        echo "${buckets}" | while read -r bucket_name; do
            if [ -n "${bucket_name}" ]; then
                echo "  - ${bucket_name}"
            fi
        done
        return 0
    fi
    
    print_warning "Found S3 buckets:"
    echo "${buckets}" | while read -r bucket_name; do
        if [ -n "${bucket_name}" ]; then
            echo "  - ${bucket_name}"
        fi
    done
    echo ""
    
    echo "${buckets}" | while read -r bucket_name; do
        if [ -n "${bucket_name}" ]; then
            print_info "Deleting S3 bucket: ${bucket_name}"
            aws --region "${aws_region}" s3 rb "s3://${bucket_name}" --force 2>/dev/null || print_warning "Failed to delete bucket: ${bucket_name}"
        fi
    done
}

# Function to delete EC2 resources
delete_ec2_resources() {
    local cluster_name="$1"
    local aws_region="$2"
    local dry_run="$3"
    
    print_info "Processing EC2 resources containing: ${cluster_name}"
    
    local instances=$(find_ec2_instances "${cluster_name}" "${aws_region}")
    local volumes=$(find_ec2_volumes "${cluster_name}" "${aws_region}")
    
    if [ -z "${instances}" ] && [ -z "${volumes}" ]; then
        print_info "No EC2 resources found containing: ${cluster_name}"
        return 0
    fi
    
    if [ "${dry_run}" = true ]; then
        if [ -n "${instances}" ]; then
            print_warning "Found EC2 instances:"
            echo "${instances}" | while read -r instance_id; do
                if [ -n "${instance_id}" ]; then
                    echo "  - ${instance_id}"
                fi
            done
        fi
        
        if [ -n "${volumes}" ]; then
            print_warning "Found EBS volumes:"
            echo "${volumes}" | while read -r volume_id; do
                if [ -n "${volume_id}" ]; then
                    echo "  - ${volume_id}"
                fi
            done
        fi
        return 0
    fi
    
    if [ -n "${instances}" ]; then
        print_warning "Found EC2 instances:"
        echo "${instances}" | while read -r instance_id; do
            if [ -n "${instance_id}" ]; then
                echo "  - ${instance_id}"
            fi
        done
        echo ""
        
        echo "${instances}" | while read -r instance_id; do
            if [ -n "${instance_id}" ]; then
                print_info "Terminating EC2 instance: ${instance_id}"
                aws --region "${aws_region}" ec2 terminate-instances --instance-ids "${instance_id}" 2>/dev/null || print_warning "Failed to terminate instance: ${instance_id}"
            fi
        done
    fi
    
    if [ -n "${volumes}" ]; then
        print_warning "Found EBS volumes:"
        echo "${volumes}" | while read -r volume_id; do
            if [ -n "${volume_id}" ]; then
                echo "  - ${volume_id}"
            fi
        done
        echo ""
        
        echo "${volumes}" | while read -r volume_id; do
            if [ -n "${volume_id}" ]; then
                print_info "Deleting EBS volume: ${volume_id}"
                aws --region "${aws_region}" ec2 delete-volume --volume-id "${volume_id}" 2>/dev/null || print_warning "Failed to delete volume: ${volume_id}"
            fi
        done
    fi
}

# Function to delete Load Balancers
delete_load_balancers() {
    local cluster_name="$1"
    local aws_region="$2"
    local dry_run="$3"
    
    print_info "Processing Load Balancers containing: ${cluster_name}"
    
    local load_balancers=$(find_load_balancers "${cluster_name}" "${aws_region}")
    
    if [ -z "${load_balancers}" ]; then
        print_info "No Load Balancers found containing: ${cluster_name}"
        return 0
    fi
    
    if [ "${dry_run}" = true ]; then
        print_warning "Found Load Balancers:"
        echo "${load_balancers}" | while read -r lb_arn; do
            if [ -n "${lb_arn}" ]; then
                echo "  - ${lb_arn}"
            fi
        done
        return 0
    fi
    
    print_warning "Found Load Balancers:"
    echo "${load_balancers}" | while read -r lb_arn; do
        if [ -n "${lb_arn}" ]; then
            echo "  - ${lb_arn}"
        fi
    done
    echo ""
    
    echo "${load_balancers}" | while read -r lb_arn; do
        if [ -n "${lb_arn}" ]; then
            print_info "Deleting Load Balancer: ${lb_arn}"
            aws --region "${aws_region}" elbv2 delete-load-balancer --load-balancer-arn "${lb_arn}" 2>/dev/null || print_warning "Failed to delete load balancer: ${lb_arn}"
        fi
    done
}

# Main function
main() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 <cluster-name> [aws-region] [--dry-run]"
        echo ""
        echo "Arguments:"
        echo "  cluster-name : Name of the cluster to delete resources for"
        echo "  aws-region  : AWS region (default: us-east-1)"
        echo "  --dry-run   : Show what would be deleted without actually deleting"
        echo ""
        echo "Examples:"
        echo "  $0 weli-test"
        echo "  $0 weli-test us-east-2"
        echo "  $0 weli-test us-east-1 --dry-run"
        echo ""
        echo "This script will delete:"
        echo "  - Route53 records in qe.devcluster.openshift.com"
        echo "  - CloudFormation stacks containing the cluster name"
        echo "  - S3 buckets containing the cluster name"
        echo "  - EC2 instances and volumes with cluster name in tags"
        echo "  - Load Balancers containing the cluster name"
        exit 1
    fi

    local cluster_name="$1"
    local aws_region="us-east-1"
    local dry_run=false

    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                aws_region="$1"
                shift
                ;;
        esac
    done

    echo "=== Delete Orphaned Cluster Resources ==="
    print_info "Cluster Name: ${cluster_name}"
    print_info "AWS Region: ${aws_region}"
    if [ "${dry_run}" = true ]; then
        print_warning "DRY RUN MODE - No resources will be actually deleted"
    fi
    echo ""

    if [ "${dry_run}" = false ]; then
        print_warning "This will delete ALL resources associated with cluster '${cluster_name}'"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Operation cancelled"
            exit 0
        fi
    fi

    echo ""

    # Process resources in order
    delete_route53_records "${cluster_name}" "${aws_region}" "${dry_run}"
    echo ""
    
    delete_cloudformation_stacks "${cluster_name}" "${aws_region}" "${dry_run}"
    echo ""
    
    delete_s3_buckets "${cluster_name}" "${aws_region}" "${dry_run}"
    echo ""
    
    delete_ec2_resources "${cluster_name}" "${aws_region}" "${dry_run}"
    echo ""
    
    delete_load_balancers "${cluster_name}" "${aws_region}" "${dry_run}"
    echo ""

    if [ "${dry_run}" = true ]; then
        print_info "Dry run completed - no resources were actually deleted"
    else
        print_success "Cluster resource deletion completed!"
        print_info "Note: Some resources may take time to fully delete"
        print_info "You can run the cluster destroy status check script to verify cleanup"
    fi
}

# Run main function
main "$@"