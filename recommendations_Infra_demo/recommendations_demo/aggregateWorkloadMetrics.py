import pandas as pd
import os
import sys

# Get filename from command line argument
filename = sys.argv[1]

# Load the CSV file into a pandas DataFrame
df = pd.read_csv(filename)

#Remove the rows if there is no owner_kind, owner_name and workload
# Expected to ignore rows which can be pods / invalid
columns_to_check = ['owner_kind', 'owner_name', 'workload', 'workload_type']
df = df.dropna(subset=columns_to_check, how='any')

# Create a column with k8_object_type
# Based on the data observed, these are the assumptions:
# If owner_kind is 'ReplicaSet' and workload is '<none>', actual workload_type is ReplicaSet
# If owner_kind is 'ReplicationCOntroller' and workload is '<none>', actual workload_type is ReplicationController
# If owner_kind and workload has some names, workload_type is same as derived through queries.

df['k8_object_type'] = ''
for i, row in df.iterrows():
    if row['owner_kind'] == 'ReplicaSet' and row['workload'] == '<none>':
        df.at[i, 'k8_object_type'] = 'replicaset'
    elif row['owner_kind'] == 'ReplicationController' and row['workload'] == '<none>':
        df.at[i, 'k8_object_type'] = 'replicationcontroller'
    else:
        df.at[i, 'k8_object_type'] = row['workload_type']

# Update k8_object_name based on the type and workload.
# If the workload is <none> (which indicates ReplicaSet and ReplicationCOntroller - ignoring pods/invalid cases), the name of the k8_object can be owner_name.
# If the workload has some other name, the k8_object_name is same as workload. In this case, owner_name cannot be used as there can be multiple owner_names for the same deployment(considering there are multiple replicasets)
df['k8_object_name'] = ''
for i, row in df.iterrows():
    if row['workload'] != '<none>':
        df.at[i, 'k8_object_name'] = row['workload']
    else:
        df.at[i, 'k8_object_name'] = row['owner_name']

df.to_csv('cop-withobjType.csv', index=False)

# Specify the columns to sort by
# Sort and grpup the data based on below columns to get a container for a workload and for an interval.
# Each file generated is for a single timestamp and a container for a workload and will be aggregated to a single metrics value.
#sort_columns = ['namespace', 'k8_object_type', 'owner_name', 'image_name', 'container_name', 'interval_start'] 
sort_columns = ['namespace', 'k8_object_type', 'workload', 'container_name', 'interval_start']
sorted_df = df.sort_values(sort_columns)

# Group the rows by the unique values
grouped = sorted_df.groupby(sort_columns)

# Create a directory to store the output CSV files
output_dir = 'output'
if not os.path.exists(output_dir):
    os.makedirs(output_dir)

# Write each group to a separate CSV file
counter = 0
for key, group in grouped:
    counter += 1
    filename = f"file_{counter}.csv"
#    filename = '_'.join(str(x) for x in key) + '.csv'
    filepath = os.path.join(output_dir, filename)
    group.to_csv(filepath, index=False)


#Create a temporary file with a header to append the aggregate data from multiple files.
# Extract the header row
header_row = df.columns.tolist()
agg_df = pd.DataFrame(columns=header_row)
columns_to_ignore = ['pod', 'owner_name', 'node' , 'resource_id']

for filename in os.listdir(output_dir):
    if filename.endswith('.csv'):
        filepath = os.path.join(output_dir, filename)
        df = pd.read_csv(filepath)
       
        # Calculate the average and minimum values for specific columns
        for column in df.columns:
            if column.endswith('avg'):
                avg = df[column].mean()
                df[column] = avg
            elif column.endswith('min'):
                minimum = df[column].min()
                df[column] = minimum
            elif column.endswith('max'):
                maximum = df[column].max()
                df[column] = maximum
            elif column.endswith('sum'):
                total = df[column].sum()
                df[column] = total
        
        df = df.drop_duplicates(subset=[col for col in df.columns if col not in columns_to_ignore])
        agg_df = agg_df.append(df)

agg_df.to_csv('final.csv', index=False)

#columns_to_ignore = ['pod', 'owner_name', 'node' , 'resource_id']
# Drop the columns like mentioned as they are only one of the value for a workload type.
# For a deployment work_type, only one pod value is picked irrespective of multiple pods as the metrics are aggregated. This is optional
df1 = pd.read_csv('final.csv')
df1.drop(columns_to_ignore, axis=1, inplace=True)

df1.to_csv('metrics.csv', index=False)
